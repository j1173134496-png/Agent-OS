[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.1\rollback-report.json'
}

$composePath = Join-Path $root 'deployment\compose.yaml'
$rollbackComposePath = Join-Path $root 'deployment\rollback\v0.3.0\compose.override.yaml'
$backupDir = Join-Path $root 'deployment\runtime\v0.3.1\rollback-backup'
$rollbackRoot = Join-Path $root 'deployment\rollback\v0.3.0'
$rollbackRequiredFiles = @(
    (Join-Path $rollbackRoot 'agentos-entrypoint.sh'),
    (Join-Path $rollbackRoot 'agentos-runtime\pluginRouter.js'),
    (Join-Path $rollbackRoot 'agentos-runtime\capabilityGate.js'),
    (Join-Path $rollbackRoot 'plugins\catalog.json'),
    (Join-Path $rollbackRoot 'branding\agentos-plugins.js'),
    (Join-Path $rollbackRoot 'branding\agentos-theme.css'),
    (Join-Path $rollbackRoot 'branding\logo-mark.png')
)
$composeText = if (Test-Path -LiteralPath $composePath) { [IO.File]::ReadAllText($composePath) } else { '' }
$apiImageMatch = [regex]::Match($composeText, '(?m)^\s*image:\s*(agentos/librechat@sha256:[0-9a-f]{64})\s*$')
$activeImage = if ($apiImageMatch.Success) { $apiImageMatch.Groups[1].Value } else { '' }
$activeDigest = if ($activeImage -match '@(sha256:[0-9a-f]{64})$') { $matches[1] } else { '' }
$rollbackDigest = 'sha256:a950bb5fe847ae3b00797bf02d0b26bcd4c12f27240ebad6fa9eedafefc59d52'
$rollbackImage = "registry.librechat.ai/danny-avila/librechat@$rollbackDigest"
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Name, [bool]$Condition, [string]$Detail, [string]$Evidence = '')
    $checks.Add([ordered]@{
            name = $Name
            status = if ($Condition) { 'PASS' } else { 'FAIL' }
            detail = $Detail
            evidence = $Evidence
        })
}

function Get-FileSummary {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ exists = $false; file_count = 0; total_bytes = 0 }
    }
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)
    return [ordered]@{
        exists = $true
        file_count = $files.Count
        total_bytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    }
}

function Get-MongoSummary {
    $query = 'JSON.stringify(Object.fromEntries(db.getCollectionNames().map(function(name){ return [name, db.getCollection(name).countDocuments({})]; })))'
    $raw = ((& docker exec agentos-mongodb mongosh --quiet LibreChat --eval $query 2>&1) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return $raw | ConvertFrom-Json } catch { return $null }
}

function Get-ContainerImageId {
    $value = ((& docker inspect agentos-api --format '{{.Image}}' 2>$null) -join '').Trim()
    return $value
}

function Test-ContainerFiles {
    param([string[]]$Paths)
    $checks = ($Paths | ForEach-Object { "test -f '$($_)'" }) -join ' && '
    $result = ((& docker exec agentos-api sh -lc "$checks && echo PASS || echo FAIL" 2>$null) -join '').Trim()
    return $result -eq 'PASS'
}

function Test-ContainerPathsAbsent {
    param([string[]]$Paths)
    $checks = ($Paths | ForEach-Object { "test ! -e '$($_)'" }) -join ' && '
    $result = ((& docker exec agentos-api sh -lc "$checks && echo PASS || echo FAIL" 2>$null) -join '').Trim()
    return $result -eq 'PASS'
}

function Wait-Ready {
    param([int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try {
            $response = Invoke-WebRequest -Uri 'http://localhost:3080/readyz' -UseBasicParsing -TimeoutSec 5
            if ([int]$response.StatusCode -eq 200 -and $response.Content.Trim() -eq 'OK') { return $true }
        } catch { }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Invoke-Compose {
    param([string[]]$Arguments)
    & docker compose @Arguments
    return $LASTEXITCODE
}

$composeArgs = @('--project-name', 'agentos', '--env-file', $EnvPath, '-f', $composePath)
$rollbackArgs = @('--project-name', 'agentos', '--env-file', $EnvPath, '-f', $composePath, '-f', $rollbackComposePath)
$beforeMongo = $null
$afterMongo = $null
$beforeUploads = Get-FileSummary -Path (Join-Path $root 'deployment\uploads')
$afterUploads = $null
$switchedToRollback = $false
$restoredActive = $false
$backupManifestPath = $null
$failureDetail = ''

try {
    Add-Check 'rollback_image_available' ($null -ne (& docker image inspect $rollbackImage 2>$null)) 'The V0.3.0 rollback image is available locally.' 'docker image inspect'
    Add-Check 'rollback_bundle_exists' (Test-Path -LiteralPath $rollbackComposePath) 'The rollback Compose override exists.' 'deployment/rollback/v0.3.0/compose.override.yaml'
    $missingRollbackFiles = @($rollbackRequiredFiles | Where-Object { -not (Test-Path -LiteralPath $_) })
    Add-Check 'rollback_bundle_complete' ($missingRollbackFiles.Count -eq 0) 'The complete V0.3.0 overlay bundle is present before switch.' (($missingRollbackFiles | ForEach-Object { [IO.Path]::GetRelativePath($root, $_).Replace('\', '/') }) -join ', ')
    Add-Check 'active_digest_before' ($apiImageMatch.Success -and -not [string]::IsNullOrWhiteSpace($activeDigest)) 'The active Compose file points to an immutable V0.3.1 API digest before rehearsal.' 'deployment/compose.yaml'
    Add-Check 'active_service_before' ($apiImageMatch.Success -and (Get-ContainerImageId) -eq ((& docker image inspect $activeImage --format '{{.Id}}' 2>$null) -join '').Trim()) 'The running API container starts on the V0.3.1 image.' 'docker inspect agentos-api'

    $beforeMongo = Get-MongoSummary
    Add-Check 'mongo_summary_before' ($null -ne $beforeMongo) 'MongoDB collection counts were captured before rollback.' 'mongosh collection count'
    Add-Check 'uploads_summary_before' $beforeUploads.exists 'Upload storage summary was captured before rollback.' 'deployment/uploads'

    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $mongoArchive = Join-Path $backupDir ("mongodb-$stamp.archive")
    & docker exec agentos-mongodb mongodump --quiet --db LibreChat --archive=/tmp/agentos-v031-rollback.archive
    $dumpExit = $LASTEXITCODE
    if ($dumpExit -eq 0) {
        & docker cp 'agentos-mongodb:/tmp/agentos-v031-rollback.archive' $mongoArchive | Out-Null
        & docker exec agentos-mongodb rm -f /tmp/agentos-v031-rollback.archive | Out-Null
    }
    Copy-Item -LiteralPath $composePath -Destination (Join-Path $backupDir "compose-$stamp.yaml") -Force
    Copy-Item -LiteralPath (Join-Path $root 'deployment\librechat.yaml') -Destination (Join-Path $backupDir "librechat-$stamp.yaml") -Force
    $backupManifest = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        mongo_dump_status = if ($dumpExit -eq 0) { 'PASS' } else { 'FAIL' }
        mongo_archive = if ($dumpExit -eq 0) { [IO.Path]::GetRelativePath($root, $mongoArchive).Replace('\', '/') } else { $null }
        config_backup_status = 'PASS'
        uploads_summary = $beforeUploads
        api_key_copied = $false
    }
    $backupManifestPath = Join-Path $backupDir 'backup-manifest.json'
    [IO.File]::WriteAllText($backupManifestPath, ($backupManifest | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    Add-Check 'backup_created' ($dumpExit -eq 0 -and (Test-Path -LiteralPath $mongoArchive)) 'MongoDB, Compose, and LibreChat configuration backup artifacts were created without copying .env.' ([IO.Path]::GetRelativePath($root, $backupManifestPath).Replace('\', '/'))

    $rollbackExit = Invoke-Compose -Arguments ($rollbackArgs + @('up', '-d', '--force-recreate', 'api'))
    $switchedToRollback = $rollbackExit -eq 0
    $rollbackReady = $switchedToRollback -and (Wait-Ready -Seconds $TimeoutSec)
    $rollbackImageId = ((& docker image inspect $rollbackImage --format '{{.Id}}' 2>$null) -join '').Trim()
    Add-Check 'rollback_switch' $switchedToRollback 'The API service was recreated with the V0.3.0 rollback image.' 'docker compose rollback override'
    Add-Check 'rollback_ready' $rollbackReady 'The V0.3.0 rollback service returned HTTP 200/OK on /readyz.' 'http://localhost:3080/readyz'
    Add-Check 'rollback_container_image' ((Get-ContainerImageId) -eq $rollbackImageId) 'The running API container image matches the V0.3.0 rollback digest.' 'docker inspect agentos-api'
    $rollbackOverlayLoaded = $rollbackReady -and (Test-ContainerFiles -Paths @('/app/agentos-entrypoint.sh', '/app/agentos/runtime/pluginRouter.js', '/app/agentos/runtime/capabilityGate.js', '/app/agentos/catalog.json', '/app/client/dist/assets/agentos-plugins.js', '/app/client/dist/assets/agentos-theme.css', '/app/client/dist/assets/logo-mark.png'))
    Add-Check 'rollback_overlay_loaded' $rollbackOverlayLoaded 'The running rollback container contains the full V0.3.0 runtime, catalog, and branding overlay.' 'docker exec agentos-api file checks'
} catch {
    $failureDetail = $_.Exception.Message
    Add-Check 'rollback_harness' $false $failureDetail
} finally {
    try {
        $restoreExit = Invoke-Compose -Arguments ($composeArgs + @('up', '-d', '--force-recreate', 'api'))
        $restoredActive = $restoreExit -eq 0
        $restoreReady = $restoredActive -and (Wait-Ready -Seconds $TimeoutSec)
        $activeImageId = ((& docker image inspect $activeImage --format '{{.Id}}' 2>$null) -join '').Trim()
        Add-Check 'active_restore' $restoredActive 'The API service was recreated with the V0.3.1 image.' 'docker compose active configuration'
        Add-Check 'active_restore_ready' $restoreReady 'The restored V0.3.1 service returned HTTP 200/OK on /readyz.' 'http://localhost:3080/readyz'
        Add-Check 'active_container_image_after' ((Get-ContainerImageId) -eq $activeImageId) 'The running API container matches the pinned V0.3.1 image after restore.' 'docker inspect agentos-api'
        $activeOverlayRemoved = $restoreReady -and (Test-ContainerPathsAbsent -Paths @('/app/agentos-entrypoint.sh', '/app/agentos/catalog.json', '/app/client/dist/assets/agentos-plugins.js', '/app/client/dist/assets/agentos-theme.css'))
        Add-Check 'active_overlay_removed' $activeOverlayRemoved 'The V0.3.0 overlay mounts are absent after restoring V0.3.1.' 'docker exec agentos-api path checks'
        $afterMongo = Get-MongoSummary
        $afterUploads = Get-FileSummary -Path (Join-Path $root 'deployment\uploads')
        Add-Check 'mongo_preserved' ($null -ne $beforeMongo -and $null -ne $afterMongo -and (($beforeMongo | ConvertTo-Json -Compress) -eq ($afterMongo | ConvertTo-Json -Compress))) 'MongoDB collection counts are unchanged after rollback and restore.' 'mongosh collection count comparison'
        Add-Check 'uploads_preserved' ($beforeUploads.file_count -eq $afterUploads.file_count -and $beforeUploads.total_bytes -eq $afterUploads.total_bytes) 'Upload file count and total bytes are unchanged after rollback and restore.' 'deployment/uploads summary comparison'
    } catch {
        Add-Check 'active_restore_harness' $false $_.Exception.Message
    }
}

$failed = @($checks | Where-Object status -eq 'FAIL').Count -gt 0
$report = [ordered]@{
    schema_version = 'agentos.v0.3.1.rollback-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    active_image = $activeImage
    rollback_image = $rollbackImage
    switched_to_rollback = $switchedToRollback
    restored_active = $restoredActive
    before = [ordered]@{ mongo = $beforeMongo; uploads = $beforeUploads }
    after = [ordered]@{ mongo = $afterMongo; uploads = $afterUploads }
    backup_manifest = if ($null -ne $backupManifestPath) { [IO.Path]::GetRelativePath($root, $backupManifestPath).Replace('\', '/') } else { $null }
    checks = $checks
    gate = if ($failed) { 'FAIL' } else { 'PASS' }
}
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))

Write-Host "V0.3.1 rollback rehearsal: $($report.gate). Report: $ReportPath"
if ($failed) { exit 1 }
exit 0
