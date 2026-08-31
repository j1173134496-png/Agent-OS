[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $root 'deployment\runtime\v0.2\security-report.json' }

function Read-DotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)
    $values = @{}
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

function Get-Value {
    param([hashtable]$Values, [string]$Name)
    if ($Values.ContainsKey($Name)) { return [string]$Values[$Name] }
    return ''
}

$envValues = if (Test-Path -LiteralPath $EnvPath) { Read-DotEnv -Path $EnvPath } else { @{} }
$apiKey = Get-Value -Values $envValues -Name 'AGENTOS_LLM_API_KEY'
$configPath = Join-Path $root 'deployment\librechat.yaml'
$composePath = Join-Path $root 'deployment\compose.yaml'
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param([string]$Name, [string]$Status, [string]$Detail)
    $findings.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail })
}

$ignoreOutput = & git -C $root check-ignore -q -- '.env' 2>$null
if ($LASTEXITCODE -eq 0) { Add-Finding 'env_ignored' 'PASS' 'The private .env is ignored by Git.' }
else { Add-Finding 'env_ignored' 'FAIL' 'The private .env is not ignored by Git.' }

$scanExtensions = @('.ps1', '.yaml', '.yml', '.md', '.json', '.svg', '.txt', '.example')
$scanFiles = Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
    $relative = $_.FullName.Substring($root.Length).TrimStart('\', '/')
    $parts = $relative -split '[\\/]'
    ($parts -notcontains '.git') -and ($parts -notcontains 'data') -and ($parts -notcontains 'uploads') -and ($parts -notcontains 'logs') -and ($parts -notcontains 'runtime') -and ($_.Extension -in $scanExtensions) -and ($_.Name -ne '.env')
}

$literalSecretFound = $false
if (-not [string]::IsNullOrWhiteSpace($apiKey) -and $apiKey -notmatch '^__.*__$') {
    foreach ($file in $scanFiles) {
        try {
            if ([System.IO.File]::ReadAllText($file.FullName).Contains($apiKey)) {
                $literalSecretFound = $true
                break
            }
        } catch {
            # Binary or transient files are outside the text scan surface.
        }
    }
}
if ($literalSecretFound) { Add-Finding 'api_key_not_in_repository' 'FAIL' 'The configured API key was found in a repository text file.' }
else { Add-Finding 'api_key_not_in_repository' 'PASS' 'No configured API key was found in repository text files.' }

if (Test-Path -LiteralPath $configPath) {
    $configText = [System.IO.File]::ReadAllText($configPath)
    if ($configText -match '\$\{AGENTOS_LLM_API_KEY\}' -and $configText -notmatch [regex]::Escape($apiKey)) {
        Add-Finding 'generated_config_placeholder' 'PASS' 'Generated LibreChat config uses a server-side placeholder.'
    } elseif ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -match '^__.*__$') {
        Add-Finding 'generated_config_placeholder' 'PASS' 'Generated config is relay-empty while credentials are absent.'
    } else {
        Add-Finding 'generated_config_placeholder' 'FAIL' 'Generated config does not satisfy the placeholder-only API key policy.'
    }
} else {
    Add-Finding 'generated_config_placeholder' 'FAIL' 'Generated LibreChat config is missing.'
}

$composeText = if (Test-Path -LiteralPath $composePath) { [System.IO.File]::ReadAllText($composePath) } else { '' }
$composeOkay = $composeText.Contains('CONFIG_PATH: /app/librechat.yaml') -and $composeText.Contains('ENDPOINTS:') -and $composeText.Contains('target: /app/librechat.yaml') -and $composeText.Contains('127.0.0.1:3080:3080')
if ($composeOkay) { Add-Finding 'server_side_config_mount' 'PASS' 'Compose mounts config, selects the custom endpoint server-side, and binds Web only to localhost.' }
else { Add-Finding 'server_side_config_mount' 'FAIL' 'Compose is missing server-side V0.2 wiring or the localhost-only Web binding.' }

try {
    $startup = (Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:3080/api/config' -TimeoutSec 10).Content
    if (-not [string]::IsNullOrWhiteSpace($apiKey) -and $apiKey -notmatch '^__.*__$' -and $startup.Contains($apiKey)) {
        Add-Finding 'browser_startup_payload' 'FAIL' 'The anonymous startup payload contains the configured API key.'
    } else {
        Add-Finding 'browser_startup_payload' 'PASS' 'The startup payload does not contain the configured API key.'
    }
} catch {
    Add-Finding 'browser_startup_payload' 'BLOCKED' 'localhost:3080 was unavailable during the startup-payload check.'
}

try {
    $startupHtml = (Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:3080/' -TimeoutSec 10).Content
    if (-not [string]::IsNullOrWhiteSpace($apiKey) -and $apiKey -notmatch '^__.*__$' -and $startupHtml.Contains($apiKey)) {
        Add-Finding 'browser_html_payload' 'FAIL' 'The initial HTML payload contains the configured API key.'
    } else {
        Add-Finding 'browser_html_payload' 'PASS' 'The initial HTML payload does not contain the configured API key.'
    }
} catch {
    Add-Finding 'browser_html_payload' 'BLOCKED' 'localhost:3080 was unavailable during the initial HTML payload check.'
}

$logText = ''
$logPath = Join-Path $root 'deployment\logs'
if (Test-Path -LiteralPath $logPath) {
    foreach ($file in Get-ChildItem -LiteralPath $logPath -File -Recurse -Force) {
        try { $logText += [System.IO.File]::ReadAllText($file.FullName) } catch { }
    }
}
$dockerLog = (& docker logs agentos-api 2>&1 | Out-String)
$logText += $dockerLog
if (-not [string]::IsNullOrWhiteSpace($apiKey) -and $apiKey -notmatch '^__.*__$' -and $logText.Contains($apiKey)) {
    Add-Finding 'logs_redacted' 'FAIL' 'The configured API key was found in service logs.'
} else {
    Add-Finding 'logs_redacted' 'PASS' 'The configured API key was not found in service logs.'
}

$hasFailure = @($findings | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$hasBlocked = @($findings | Where-Object { $_.status -eq 'BLOCKED' }).Count -gt 0
$gate = if ($hasFailure) { 'FAIL' } elseif ($hasBlocked) { 'BLOCKED' } else { 'PASS' }
$report = [ordered]@{
    schema_version = 'agentos.v0.2.security-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    checks = $findings
    gate = $gate
}
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

Write-Host "V0.2 security gate: $gate. Report: $ReportPath"
if ($gate -eq 'FAIL') { exit 1 }
if ($gate -eq 'BLOCKED') { exit 2 }
exit 0
