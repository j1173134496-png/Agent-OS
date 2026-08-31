[CmdletBinding()]
param(
    [string]$SourcePath,
    [string]$ReportPath,
    [switch]$RunE2E,
    [switch]$SkipUnit
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $root 'source\librechat-maintained'
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.1\full-test-report.json'
}

function Get-SafeSummary {
    param([object[]]$Output, [int]$ExitCode)

    $lines = @($Output | ForEach-Object { [string]$_ } | Where-Object {
            $_ -match '(?i)Test Suites|Tests:|Snapshots:|Time:|passed|failed|total|PASS|FAIL|test result'
        })
    $summary = ($lines -join ' ').Trim()
    $summary = [regex]::Replace($summary, '(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+', '$1[REDACTED]')
    $summary = [regex]::Replace($summary, '(?i)(api[_-]?key\s*[:=]\s*)[^\s,;]+', '$1[REDACTED]')
    if ($summary.Length -gt 800) { $summary = $summary.Substring(0, 800) }
    if ([string]::IsNullOrWhiteSpace($summary)) { $summary = "exit_code=$ExitCode" }
    return $summary
}

function Invoke-NpmCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [hashtable]$Environment = @{}
    )

    $previousErrorAction = $ErrorActionPreference
    $previousEnvironment = @{}
    foreach ($key in $Environment.Keys) {
        $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
    }
    try {
        $ErrorActionPreference = 'Continue'
        try {
            $output = @(& npm --prefix $SourcePath run $ScriptName 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorAction
        }
    } finally {
        foreach ($key in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previousEnvironment[$key], 'Process')
        }
    }
    [ordered]@{
        name = $Name
        status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        exit_code = $exitCode
        detail = Get-SafeSummary -Output $output -ExitCode $exitCode
    }
}

function Invoke-MongoMemoryServerWarmup {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][hashtable]$Environment
    )

    $previousEnvironment = @{}
    foreach ($key in $Environment.Keys) {
        $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
    }

    $warmupScript = @"
const { MongoMemoryServer } = require('mongodb-memory-server');
(async () => {
  const server = await MongoMemoryServer.create();
  console.log('mongodb_memory_server_ready');
  await server.stop();
})().catch((error) => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});
"@

    $output = @()
    $exitCode = 1
    $oldLocation = Get-Location
    try {
        Push-Location -LiteralPath $SourcePath
        $ErrorActionPreference = 'Continue'
        $output = @(& node -e $warmupScript 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
        foreach ($key in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previousEnvironment[$key], 'Process')
        }
    }

    $rawOutput = ($output | ForEach-Object { [string]$_ }) -join ' '
    $detail = Get-SafeSummary -Output $output -ExitCode $exitCode
    if ($exitCode -eq 0 -and $rawOutput -notmatch 'mongodb_memory_server_ready') {
        $exitCode = 1
        $detail = 'MongoMemoryServer warmup did not report a ready instance.'
    } elseif ($exitCode -eq 0) {
        $detail = 'mongodb_memory_server_ready'
    }
    return [ordered]@{
        name = 'mongo_memory_runtime'
        status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        exit_code = $exitCode
        detail = $detail
    }
}

function Test-TcpPort {
    param([string]$HostName, [int]$Port)

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        return $task.Wait(500) -and $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Invoke-IsolatedE2E {
    $mongoImage = 'mongo@sha256:972a9fa5d0f06418faa85d3f831ebba14e203a55dee5cd2dbcaf09490d2eff31'
    $mongoName = "agentos-v031-e2e-mongo-$PID"
    $mongoPort = 27018
    $mongoUri = "mongodb://127.0.0.1:$mongoPort/LibreChat-e2e"
    $mongoStarted = $false

    try {
        $runOutput = @(& docker run --detach --rm --name $mongoName --publish "127.0.0.1:${mongoPort}:27017" $mongoImage mongod --bind_ip_all --noauth 2>&1)
        $runExitCode = $LASTEXITCODE
        if ($runExitCode -ne 0) {
            return [ordered]@{
                name = 'mock_e2e_suite'
                status = 'FAIL'
                exit_code = $runExitCode
                detail = 'Could not start the isolated MongoDB test container.'
            }
        }
        $mongoStarted = $true
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline -and -not (Test-TcpPort -HostName '127.0.0.1' -Port $mongoPort)) {
            Start-Sleep -Milliseconds 500
        }
        if (-not (Test-TcpPort -HostName '127.0.0.1' -Port $mongoPort)) {
            return [ordered]@{
                name = 'mock_e2e_suite'
                status = 'FAIL'
                exit_code = 124
                detail = 'The isolated MongoDB test container did not become reachable.'
            }
        }

        return Invoke-NpmCheck -Name 'mock_e2e_suite' -ScriptName 'e2e:mock:ci' -Environment @{
            E2E_BASE_URL = 'http://127.0.0.1:3081'
            E2E_PORT = '3081'
            E2E_MCP_HTTP_PORT = '8765'
            E2E_USE_MEMORY_MONGO = 'false'
            MONGO_URI = $mongoUri
        }
    } finally {
        if ($mongoStarted) {
            & docker rm --force $mongoName 2>$null | Out-Null
        }
    }
}

$checks = [System.Collections.Generic.List[object]]::new()
$sourceExists = Test-Path -LiteralPath $SourcePath
$mongoTestEnvironment = @{
    MONGOMS_VERSION = '7.0.14'
    MONGOMS_DOWNLOAD_DIR = Join-Path ([IO.Path]::GetTempPath()) 'agentos-mongodb-binaries-7.0.14'
}
$checks.Add([ordered]@{
        name = 'source_tree'
        status = if ($sourceExists) { 'PASS' } else { 'FAIL' }
        exit_code = 0
        detail = if ($sourceExists) { 'The maintained LibreChat source tree exists.' } else { "Missing source tree: $SourcePath" }
    })

if ($sourceExists) {
    $checks.Add((Invoke-MongoMemoryServerWarmup -SourcePath $SourcePath -Environment $mongoTestEnvironment))
    if ($SkipUnit) {
        $checks.Add([ordered]@{
                name = 'unit_test_suite'
                status = 'NOT_RUN'
                exit_code = $null
                detail = 'Skipped by -SkipUnit.'
            })
    } else {
        $checks.Add((Invoke-NpmCheck -Name 'unit_test_suite' -ScriptName 'test:all' -Environment $mongoTestEnvironment))
    }
    if ($RunE2E) {
        $checks.Add((Invoke-IsolatedE2E))
    } else {
        $checks.Add([ordered]@{
                name = 'mock_e2e_suite'
                status = 'NOT_RUN'
                exit_code = $null
                detail = 'Run with -RunE2E to execute the complete mock Playwright suite.'
            })
    }
} else {
    $checks.Add([ordered]@{
            name = 'unit_test_suite'
            status = 'FAIL'
            exit_code = 127
            detail = 'The maintained LibreChat source tree is missing.'
        })
    $checks.Add([ordered]@{
            name = 'mock_e2e_suite'
            status = 'FAIL'
            exit_code = 127
            detail = 'The maintained LibreChat source tree is missing.'
        })
}

$failed = @($checks | Where-Object { $_.status -in @('FAIL', 'NOT_RUN') }).Count -gt 0
$report = [ordered]@{
    schema_version = 'agentos.v0.3.1.full-test-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source_path = 'source/librechat-maintained'
    checks = $checks
    gate = if ($failed) { 'FAIL' } else { 'PASS' }
}
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

Write-Host "V0.3.1 full test suite: $($report.gate). Report: $ReportPath"
if ($failed) { exit 1 }
exit 0
