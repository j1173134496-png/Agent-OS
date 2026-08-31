[CmdletBinding()]
param(
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.2\gate-report.json'
}

$checks = [System.Collections.Generic.List[object]]::new()

function Invoke-GateCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptName
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1)
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $status = switch ($exitCode) {
        0 { 'PASS'; break }
        2 { 'BLOCKED'; break }
        default { 'FAIL'; break }
    }
    $checks.Add([ordered]@{
        name = $Name
        script = $ScriptName
        status = $status
        exit_code = $exitCode
    })
    Write-Host "[$status] $Name"
    if ($status -eq 'FAIL' -and $output.Count -gt 0) {
        Write-Host (($output | Select-Object -Last 3) -join [Environment]::NewLine)
    }
}

Invoke-GateCheck -Name 'health' -ScriptName 'Health-AgentOS.ps1'
Invoke-GateCheck -Name 'local_runtime' -ScriptName 'Test-AgentOSV02Local.ps1'
Invoke-GateCheck -Name 'config_contract' -ScriptName 'Test-AgentOSV02Config.ps1'
Invoke-GateCheck -Name 'security' -ScriptName 'Test-AgentOSV02Security.ps1'
Invoke-GateCheck -Name 'secret_scan' -ScriptName 'Secret-Scan-AgentOS.ps1'
Invoke-GateCheck -Name 'relay_capability' -ScriptName 'Test-AgentOSV02Relay.ps1'
Invoke-GateCheck -Name 'model_matrix' -ScriptName 'Test-AgentOSV02ModelMatrix.ps1'
Invoke-GateCheck -Name 'conversation_regression' -ScriptName 'Test-AgentOSV02Conversation.ps1'

$hasFailure = @($checks | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$hasBlocked = @($checks | Where-Object { $_.status -eq 'BLOCKED' }).Count -gt 0
$gate = if ($hasFailure) { 'FAIL' } elseif ($hasBlocked) { 'BLOCKED' } else { 'PASS' }
$report = [ordered]@{
    schema_version = 'agentos.v0.2.gate-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    checks = $checks
    gate = $gate
}

$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

Write-Host "V0.2 aggregate gate: $gate. Report: $ReportPath"
if ($gate -eq 'FAIL') { exit 1 }
if ($gate -eq 'BLOCKED') { exit 2 }
exit 0
