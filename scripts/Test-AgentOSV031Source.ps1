[CmdletBinding()]
param(
    [string]$SourcePath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    $SourcePath = Join-Path $root 'source\librechat-maintained'
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.1\source-test-report.json'
}

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

function Invoke-JestTarget {
    param(
        [string]$Name,
        [string]$PackagePath,
        [string]$TestPath,
        [string]$EvidencePath = $TestPath
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $outputLines = @(& npm --prefix $PackagePath run test:ci -- $TestPath --runInBand --coverage=false 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $output = ($outputLines -join [Environment]::NewLine).Trim()
    $summary = @($output -split "`r?`n" | Where-Object { $_ -match '^(Test Suites|Tests|Snapshots|Time):' }) -join ' '
    $detail = if ($exitCode -eq 0) { $summary } else { "exit_code=$exitCode $summary" }
    Add-Check $Name ($exitCode -eq 0) $detail ("source/librechat-maintained/$EvidencePath")
}

try {
    Add-Check 'source_tree' (Test-Path -LiteralPath $SourcePath) 'The maintained LibreChat source tree exists.' 'source/librechat-maintained'
    Add-Check 'jest_dependency' (Test-Path -LiteralPath (Join-Path $SourcePath 'node_modules\.bin\jest')) 'Source test dependencies are installed.' 'source/librechat-maintained/node_modules/.bin/jest'

    if (@($checks | Where-Object status -eq 'FAIL').Count -eq 0) {
        Invoke-JestTarget 'reasoning_selector_tests' (Join-Path $SourcePath 'client') 'src/components/Chat/Menus/Endpoints/__tests__/agentosReasoning.test.ts' 'client/src/components/Chat/Menus/Endpoints/__tests__/agentosReasoning.test.ts'
        Invoke-JestTarget 'request_contract_tests' (Join-Path $SourcePath 'packages/data-provider') 'specs/agentos-v031-contract.spec.ts' 'packages/data-provider/specs/agentos-v031-contract.spec.ts'
        Invoke-JestTarget 'image_tool_tests' (Join-Path $SourcePath 'api') 'test/app/clients/tools/structured/OpenAIImageTools.test.js' 'api/test/app/clients/tools/structured/OpenAIImageTools.test.js'
    }
} catch {
    Add-Check 'source_test_harness' $false $_.Exception.Message
}

$failed = @($checks | Where-Object status -eq 'FAIL').Count -gt 0
$report = [ordered]@{
    schema_version = 'agentos.v0.3.1.source-test-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    checks = $checks
    gate = if ($failed) { 'FAIL' } else { 'PASS' }
}
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

Write-Host "V0.3.1 source tests: $($report.gate). Report: $ReportPath"
if ($failed) { exit 1 }
exit 0
