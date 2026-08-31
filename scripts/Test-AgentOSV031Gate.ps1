[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath,
    [string]$EvidenceDir,
    [string]$BaseUrl = 'http://localhost:3080',
    [switch]$ProbeReasoning
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($EvidenceDir)) { $EvidenceDir = Join-Path $root 'deployment\runtime\v0.3.1' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $EvidenceDir 'V0.3.1_GATE_REPORT.json'
}
$brandTitle = [string]::Concat(([char]0x7ACB).ToString(), ([char]0x80FD).ToString(), ([char]0x6D3E).ToString(), ' Agent OS')
$relayName = [string]::Concat(([char]0x4E2D).ToString(), ([char]0x8F6C).ToString())

$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$Evidence = ''
    )
    $checks.Add([ordered]@{
            name = $Name
            status = if ($Condition) { 'PASS' } else { 'FAIL' }
            detail = $Detail
            evidence = $Evidence
        })
}

function Read-DotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $value = $matches[2]
            if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$matches[1]] = $value
        }
    }
    return $values
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return [IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { return $null }
}

function Get-DelimitedValues {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @($Value -split '[,;]' | ForEach-Object { $_.Trim().Trim('''"') } | Where-Object { $_ })
}

function Get-ReleaseField {
    param([string]$Text, [string]$Field)
    $pattern = '(?m)^\|\s*' + [regex]::Escape($Field) + '\s*\|\s*(.*?)\s*\|\s*$'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ''
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { return '' }
}

function Test-GitCommit {
    param([string]$Commit)
    if ($Commit -notmatch '^[0-9a-f]{40}$') { return $false }
    $null = & git -C $root cat-file -e "$Commit^{commit}" 2>$null
    return $LASTEXITCODE -eq 0
}

function Invoke-CheckScript {
    param([string]$ScriptPath, [string]$OutputPath)
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return [pscustomobject]@{ exit_code = 127; detail = 'script_missing' }
    }
    & $ScriptPath -EnvPath $EnvPath -ReportPath $OutputPath | Out-Null
    return [pscustomobject]@{ exit_code = $LASTEXITCODE; detail = 'script_completed' }
}

function Invoke-ReportScript {
    param([string]$ScriptPath, [string]$OutputPath)
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return [pscustomobject]@{ exit_code = 127; detail = 'script_missing' }
    }
    & $ScriptPath -ReportPath $OutputPath | Out-Null
    return [pscustomobject]@{ exit_code = $LASTEXITCODE; detail = 'script_completed' }
}

function Get-RelativeEvidencePath {
    param([string]$Path)
    try { return [IO.Path]::GetRelativePath($root, $Path).Replace('\', '/') } catch { return $Path }
}

$envValues = Read-DotEnv -Path $EnvPath
$configPath = Join-Path $root 'deployment\librechat.yaml'
$composePath = Join-Path $root 'deployment\compose.yaml'
$configReportPath = Join-Path $EvidenceDir 'config-report.json'
$reasoningReportPath = Join-Path $EvidenceDir 'reasoning-matrix.json'
$sourceTestReportPath = Join-Path $EvidenceDir 'source-test-report.json'
$brandingReportPath = Join-Path $EvidenceDir 'branding-report.json'
$imageMatrixPath = Join-Path $root 'deployment\runtime\v0.2\model-matrix.json'
$uiEvidencePath = Join-Path $EvidenceDir 'ui-evidence.json'
$regressionEvidencePath = Join-Path $EvidenceDir 'conversation-regression.json'
$releaseRecordPath = Join-Path $root 'docs\releases\V0.3.1_RELEASE_RECORD.md'
$rollbackReportPath = Join-Path $EvidenceDir 'rollback-report.json'
$fullTestReportPath = Join-Path $EvidenceDir 'full-test-report.json'
$configText = if (Test-Path -LiteralPath $configPath) { [IO.File]::ReadAllText($configPath) } else { '' }
$composeText = if (Test-Path -LiteralPath $composePath) { [IO.File]::ReadAllText($composePath) } else { '' }

$configResult = Invoke-CheckScript -ScriptPath (Join-Path $PSScriptRoot 'Test-AgentOSV031Config.ps1') -OutputPath $configReportPath
$configReport = Read-JsonFile -Path $configReportPath
Add-Check 'config_contract' ($configResult.exit_code -eq 0 -and $null -ne $configReport -and $configReport.gate -eq 'PASS') 'The V0.3.1 configuration contract passes.' (Get-RelativeEvidencePath $configReportPath)

$sourceTestResult = Invoke-ReportScript -ScriptPath (Join-Path $PSScriptRoot 'Test-AgentOSV031Source.ps1') -OutputPath $sourceTestReportPath
$sourceTestReport = Read-JsonFile -Path $sourceTestReportPath
Add-Check 'source_tests' ($sourceTestResult.exit_code -eq 0 -and $null -ne $sourceTestReport -and $sourceTestReport.schema_version -eq 'agentos.v0.3.1.source-test-report.v1' -and $sourceTestReport.gate -eq 'PASS') 'The V0.3.1 targeted source tests pass.' (Get-RelativeEvidencePath $sourceTestReportPath)

$brandingResult = Invoke-ReportScript -ScriptPath (Join-Path $PSScriptRoot 'Test-AgentOSBranding.ps1') -OutputPath $brandingReportPath
$brandingReport = Read-JsonFile -Path $brandingReportPath
Add-Check 'branding_regression' ($brandingResult.exit_code -eq 0 -and $null -ne $brandingReport -and $brandingReport.schema_version -eq 'agentos.v0.3.1.branding-report.v1' -and $brandingReport.gate -eq 'PASS') 'Branding replacement is limited to /assets/ and cannot rewrite generated message images.' (Get-RelativeEvidencePath $brandingReportPath)

$imageMatrix = Read-JsonFile -Path $imageMatrixPath
$configuredImageModels = Get-DelimitedValues -Value ([string]$envValues['AGENTOS_IMAGE_MODELS'])
if ($configuredImageModels.Count -eq 0) {
    $configuredImageModels = @([string]$envValues['AGENTOS_IMAGE_MODEL']) | Where-Object { $_ }
}
$imageMatrixResults = if ($null -ne $imageMatrix) { @($imageMatrix.results | Where-Object { $_.name -eq 'image_generation' }) } else { @() }
$expectedImageSet = @($configuredImageModels | Sort-Object -Unique)
$actualImageSet = @($imageMatrixResults | ForEach-Object { [string]$_.model } | Sort-Object -Unique)
$imageModelsMatch = ($expectedImageSet -join '|') -eq ($actualImageSet -join '|')
$imageResultsPass = $imageMatrixResults.Count -eq $expectedImageSet.Count -and
    @($imageMatrixResults | Where-Object { $_.status -ne 'PASS' }).Count -eq 0
$imageMatrixComplete = $null -ne $imageMatrix -and
    $imageMatrix.schema_version -eq 'agentos.v0.2.model-matrix.v1' -and
    $imageMatrix.gate -eq 'PASS' -and
    [string]$imageMatrix.default_image_model -eq [string]$envValues['AGENTOS_IMAGE_MODEL'] -and
    $imageModelsMatch -and $imageResultsPass
Add-Check 'image_generation_matrix' $imageMatrixComplete 'The configured image models passed the live relay generation matrix.' (Get-RelativeEvidencePath $imageMatrixPath)

if ($ProbeReasoning) {
    $reasoningResult = Invoke-CheckScript -ScriptPath (Join-Path $PSScriptRoot 'Test-AgentOSV031Reasoning.ps1') -OutputPath $reasoningReportPath
    Add-Check 'reasoning_probe_command' ($reasoningResult.exit_code -eq 0) 'The live reasoning probe completed successfully.' (Get-RelativeEvidencePath $reasoningReportPath)
}
$reasoningReport = Read-JsonFile -Path $reasoningReportPath
$reasoningModels = @('gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5')
$reasoningLevels = @('low', 'medium', 'high')
$preferredProtocol = [string]$envValues['AGENTOS_LLM_PROTOCOL']
if ([string]::IsNullOrWhiteSpace($preferredProtocol)) { $preferredProtocol = 'chat_completions' }
$preferredProtocolStatus = if ($null -ne $reasoningReport) {
    [string](@($reasoningReport.protocols | Where-Object protocol -eq $preferredProtocol | Select-Object -First 1).status)
} else { '' }
$reasoningComplete = $null -ne $reasoningReport -and $reasoningReport.gate -eq 'PASS' -and
    [string]$reasoningReport.preferred_protocol -eq $preferredProtocol -and
    [string]$reasoningReport.protocol -eq $preferredProtocol -and
    $preferredProtocolStatus -eq 'PASS' -and
    $reasoningReport.streaming.status -eq 'PASS'
Add-Check 'reasoning_preferred_protocol' $reasoningComplete "The configured protocol $preferredProtocol passed protocol, reasoning, and streaming probes." (Get-RelativeEvidencePath $reasoningReportPath)
foreach ($model in $reasoningModels) {
    $entry = @($reasoningReport.models | Where-Object model -eq $model) | Select-Object -First 1
    $supported = if ($null -ne $entry) { @($entry.supported_levels) } else { @() }
    $missing = @($reasoningLevels | Where-Object { $_ -notin $supported })
    Add-Check ("reasoning_matrix_$model") ($reasoningComplete -and $missing.Count -eq 0) "The reasoning matrix covers low/medium/high for $model." (Get-RelativeEvidencePath $reasoningReportPath)
}
Add-Check 'reasoning_streaming' ($reasoningComplete) 'The selected protocol has a streaming response probe.' (Get-RelativeEvidencePath $reasoningReportPath)

$legacyPaths = @(
    (Join-Path $root 'deployment\agentos-entrypoint.sh'),
    (Join-Path $root 'deployment\branding\agentos-plugins.js'),
    (Join-Path $root 'deployment\branding\agentos-theme.css'),
    (Join-Path $root 'deployment\agentos-runtime'),
    (Join-Path $root 'deployment\plugins')
)
$activeLegacy = @($legacyPaths | Where-Object { Test-Path -LiteralPath $_ })
Add-Check 'legacy_overlay_isolated' ($activeLegacy.Count -eq 0) 'The legacy overlay is absent from the active deployment directory.' (($activeLegacy | ForEach-Object { Get-RelativeEvidencePath $_ }) -join ', ')
Add-Check 'compose_has_no_legacy_overlay' ($composeText -notmatch '(?i)agentos-entrypoint|agentos-runtime|agentos_plugin_ids|agentos-plugins\.js') 'Compose does not load the legacy overlay.' (Get-RelativeEvidencePath $composePath)

$expectedDigest = 'sha256:a59d8926a97a2d7387700c746d6b0ba8e88c352ecd47de0fe0bd7cc4b1ebdcf1'
$digestMatch = $composeText -match [regex]::Escape("agentos/librechat@$expectedDigest")
Add-Check 'api_image_digest' $digestMatch 'Compose pins the expected V0.3.1 API image digest.' (Get-RelativeEvidencePath $composePath)
Add-Check 'api_image_available' ($null -ne (& docker image inspect ("agentos/librechat@$expectedDigest") 2>$null)) 'The pinned V0.3.1 API image is available locally.' 'docker image inspect'
$runningDigest = ((& docker inspect agentos-api --format '{{.Config.Image}}' 2>$null) -join '').Trim()
Add-Check 'running_api_image_digest' ($runningDigest -eq "agentos/librechat@$expectedDigest") 'The running API container uses the pinned V0.3.1 image digest.' 'docker inspect agentos-api'

if (-not (Test-Path -LiteralPath $EvidenceDir)) { New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null }
$runtimeOk = $true
try {
    $ready = Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + '/readyz') -UseBasicParsing -TimeoutSec 15
    $runtimeOk = [int]$ready.StatusCode -eq 200 -and $ready.Content.Trim() -eq 'OK'
} catch { $runtimeOk = $false }
Add-Check 'runtime_ready' $runtimeOk 'The local service readiness endpoint returns HTTP 200 and OK.' "$BaseUrl/readyz"

$homeResponse = $null
try { $homeResponse = Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + '/') -UseBasicParsing -TimeoutSec 15 } catch { }
$homeText = if ($null -ne $homeResponse) { [string]$homeResponse.Content } else { '' }
Add-Check 'home_brand_title' ($homeText -match ('<title>' + [regex]::Escape($brandTitle) + '</title>')) 'The served page has the AgentOS title.' "$BaseUrl/"
Add-Check 'home_theme_color' ($homeText -match 'theme-color" content="#ff6a00"') 'The served page has the AgentOS theme color.' "$BaseUrl/"
Add-Check 'compose_footer_contract' ($composeText -match ('(?m)^\s+CUSTOM_FOOTER:\s+"' + [regex]::Escape($brandTitle) + '"\s*$')) 'Compose supplies the AgentOS footer contract.' (Get-RelativeEvidencePath $composePath)

$uiEvidence = Read-JsonFile -Path $uiEvidencePath
$requiredViewports = @('1440x900', '1920x1080', '390x844')
$uiViewportNames = if ($null -ne $uiEvidence) { @($uiEvidence.viewports | ForEach-Object { [string]$_.viewport }) } else { @() }
Add-Check 'ui_evidence_file' ($null -ne $uiEvidence -and $uiEvidence.schema_version -eq 'agentos.v0.3.1.ui-evidence.v1') 'Browser evidence has the expected schema.' (Get-RelativeEvidencePath $uiEvidencePath)
foreach ($viewport in $requiredViewports) {
    $record = @($uiEvidence.viewports | Where-Object viewport -eq $viewport) | Select-Object -First 1
    $shot = if ($null -ne $record) { [string]$record.screenshot } else { '' }
    $shotPath = if ([IO.Path]::IsPathRooted($shot)) { $shot } else { Join-Path $root ($shot -replace '/', '\') }
    $hasScreenshot = -not [string]::IsNullOrWhiteSpace($shot) -and (Test-Path -LiteralPath $shotPath)
    $hasBrand = $null -ne $record -and [string]$record.title -eq $brandTitle -and [string]$record.theme_color -eq '#ff6a00'
    $hasModels = $null -ne $record -and (@($record.model_labels).Count -eq 4) -and (@($record.model_labels | Where-Object { $_ -match ('(?i)Agent|gpt-image|' + [regex]::Escape($relayName)) }).Count -eq 0)
    $hasReasoning = $null -ne $record -and (@($record.reasoning_labels).Count -eq 3)
    $noFloating = $null -ne $record -and [int]$record.floating_capability_count -eq 0
    Add-Check ("ui_$viewport") ($hasScreenshot -and $hasBrand -and $hasModels -and $hasReasoning -and $noFloating) "Browser evidence passes the $viewport visual and selector checks." (Get-RelativeEvidencePath $uiEvidencePath)
}

$regression = Read-JsonFile -Path $regressionEvidencePath
$regressionPass = $null -ne $regression -and $regression.schema_version -eq 'agentos.v0.3.1.conversation-regression.v1' -and $regression.gate -eq 'PASS'
Add-Check 'conversation_regression' $regressionPass 'Login, ordinary conversation, streaming, and history evidence is present.' (Get-RelativeEvidencePath $regressionEvidencePath)

$fullTestReport = Read-JsonFile -Path $fullTestReportPath
$fullTestChecks = if ($null -ne $fullTestReport) { @($fullTestReport.checks) } else { @() }
$requiredFullTestNames = @('source_tree', 'unit_test_suite', 'mock_e2e_suite')
$fullTestNamesPresent = @($requiredFullTestNames | Where-Object {
        $_ -in @($fullTestChecks | ForEach-Object { [string]$_.name })
    }).Count -eq $requiredFullTestNames.Count
$fullTestPass = $null -ne $fullTestReport -and
    $fullTestReport.schema_version -eq 'agentos.v0.3.1.full-test-report.v1' -and
    $fullTestReport.gate -eq 'PASS' -and
    $fullTestNamesPresent -and
    $fullTestChecks.Count -gt 0 -and
    @($fullTestChecks | Where-Object { $_.status -ne 'PASS' }).Count -eq 0
Add-Check 'full_test_suite' $fullTestPass 'The maintained source full test suite completed successfully.' (Get-RelativeEvidencePath $fullTestReportPath)

$rollbackReport = Read-JsonFile -Path $rollbackReportPath
$expectedActiveImage = "agentos/librechat@$expectedDigest"
$expectedRollbackImage = 'registry.librechat.ai/danny-avila/librechat@sha256:a950bb5fe847ae3b00797bf02d0b26bcd4c12f27240ebad6fa9eedafefc59d52'
$rollbackImagesMatch = $null -ne $rollbackReport -and
    [string]$rollbackReport.active_image -eq $expectedActiveImage -and
    [string]$rollbackReport.rollback_image -eq $expectedRollbackImage
Add-Check 'rollback_rehearsal' ($rollbackImagesMatch -and $rollbackReport.schema_version -eq 'agentos.v0.3.1.rollback-report.v1' -and $rollbackReport.gate -eq 'PASS' -and $rollbackReport.switched_to_rollback -and $rollbackReport.restored_active) 'The V0.3.0 rollback switch and V0.3.1 restore rehearsal passed.' (Get-RelativeEvidencePath $rollbackReportPath)
$releaseText = if (Test-Path -LiteralPath $releaseRecordPath) { [IO.File]::ReadAllText($releaseRecordPath) } else { '' }
$preReleaseFailed = @($checks | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$expectedReleaseStatus = if ($preReleaseFailed) { 'GATE FAIL' } else { 'GATE PASS' }
$releaseStatus = (Get-ReleaseField -Text $releaseText -Field 'Status').Trim('`')
$releaseBaselineCommit = (Get-ReleaseField -Text $releaseText -Field 'Baseline commit').Trim('`')
$releaseConfigHash = Get-ReleaseField -Text $releaseText -Field 'Configuration hash'
$releaseTestSummary = Get-ReleaseField -Text $releaseText -Field 'Test summary'
$releaseKnownIssues = Get-ReleaseField -Text $releaseText -Field 'Known issues'
$releaseRollbackTarget = Get-ReleaseField -Text $releaseText -Field 'Rollback target'
$releaseApprovers = Get-ReleaseField -Text $releaseText -Field 'Approvers'
$configHash = Get-FileSha256 -Path $configPath
$composeHash = Get-FileSha256 -Path $composePath
$reasoningConfigHash = Get-FileSha256 -Path (Join-Path $root 'deployment\agentos-reasoning-matrix.json')
$releaseComplete =
    $releaseText -match '(?m)^# AgentOS V0\.3\.1 Release Record\s*$' -and
    (Get-ReleaseField -Text $releaseText -Field 'Version').Trim('`') -eq 'V0.3.1' -and
    $releaseStatus -eq $expectedReleaseStatus -and
    (Test-GitCommit -Commit $releaseBaselineCommit) -and
    $releaseText.Contains('LibreChat `v0.8.7`') -and
    $releaseText.Contains($expectedActiveImage) -and
    $releaseText.Contains($expectedRollbackImage) -and
    $releaseConfigHash.Contains("deployment/librechat.yaml: sha256:$configHash") -and
    $releaseConfigHash.Contains("deployment/compose.yaml: sha256:$composeHash") -and
    $releaseConfigHash.Contains("deployment/agentos-reasoning-matrix.json: sha256:$reasoningConfigHash") -and
    $releaseText -match '(?m)^\| Release date \| `\d{4}-\d{2}-\d{2}` \|' -and
    $releaseText.Contains('AOS-031-01') -and $releaseText.Contains('AOS-031-09') -and
    $releaseTestSummary.Contains('unit_test_suite=PASS') -and
    $releaseTestSummary.Contains('mock_e2e_suite=PASS') -and
    $releaseTestSummary.Contains('image_generation=PASS') -and
    $releaseKnownIssues.Contains('V0.3.2') -and
    $releaseRollbackTarget.Contains('V0.3.0') -and
    $releaseRollbackTarget.Contains($expectedRollbackImage) -and
    -not [string]::IsNullOrWhiteSpace($releaseApprovers) -and
    $releaseText.Contains('V0.3.1_GATE_REPORT.json') -and
    $releaseText.Contains('reasoning-matrix.json') -and
    $releaseText.Contains('rollback-report.json') -and
    $releaseText.Contains('model-matrix.json')
Add-Check 'release_record' $releaseComplete "The V0.3.1 release record matches the expected $expectedReleaseStatus result and current evidence." (Get-RelativeEvidencePath $releaseRecordPath)

$failed = @($checks | Where-Object status -eq 'FAIL').Count -gt 0
$report = [ordered]@{
    schema_version = 'agentos.v0.3.1.gate-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    release = 'V0.3.1'
    base_url = $BaseUrl
    checks = $checks
    gate = if ($failed) { 'FAIL' } else { 'PASS' }
}
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

Write-Host "V0.3.1 Gate: $($report.gate). Report: $ReportPath"
if ($failed) { exit 1 }
exit 0
