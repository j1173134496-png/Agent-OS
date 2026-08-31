[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $root 'deployment\runtime\v0.2\local-report.json' }

function Get-DotEnvValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match "^\s*$([regex]::Escape($Name))\s*=\s*(.*?)\s*$") {
            return $matches[1].Trim('''"')
        }
    }
    return ''
}

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail)
    $checks.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail })
}

$brandName = (-join ([char[]](0x7ACB, 0x80FD, 0x6D3E))) + ' Agent OS'
$brandDescription = $brandName + ' - ' + (-join ([char[]](0x4F01, 0x4E1A, 0x667A, 0x80FD, 0x5DE5, 0x4F5C, 0x53F0)))

function Check-Http {
    param([string]$Name, [string]$Uri, [string]$ExpectedBody = '', [hashtable]$Headers)
    try {
        $requestParams = @{ UseBasicParsing = $true; Uri = $Uri; TimeoutSec = 10 }
        if ($Headers) { $requestParams.Headers = $Headers }
        $response = Invoke-WebRequest @requestParams
        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
            throw "Unexpected HTTP status $($response.StatusCode)."
        }
        if ($ExpectedBody -and $response.Content.Trim() -ne $ExpectedBody) {
            throw 'Unexpected response body.'
        }
        Add-Check $Name 'PASS' "HTTP $($response.StatusCode)"
        return $response
    } catch {
        Add-Check $Name 'FAIL' $_.Exception.Message
        return $null
    }
}

$checks = [System.Collections.Generic.List[object]]::new()
$envText = if (Test-Path -LiteralPath $EnvPath) { [System.IO.File]::ReadAllText($EnvPath) } else { '' }
$apiKey = Get-DotEnvValue -Path $EnvPath -Name 'AGENTOS_LLM_API_KEY'
$configPath = Join-Path $root 'deployment\librechat.yaml'
$composePath = Join-Path $root 'deployment\compose.yaml'
$configText = if (Test-Path -LiteralPath $configPath) { [System.IO.File]::ReadAllText($configPath) } else { '' }
$composeText = if (Test-Path -LiteralPath $composePath) { [System.IO.File]::ReadAllText($composePath) } else { '' }

if (-not (Test-Path -LiteralPath $EnvPath)) {
    Add-Check 'private_env' 'FAIL' 'The private .env file is missing.'
} else {
    Add-Check 'private_env' 'PASS' 'The private .env file exists.'
}

$services = @(& docker compose --project-name agentos --env-file $EnvPath -f $composePath ps --services --filter status=running 2>$null)
foreach ($required in @('api', 'mongodb')) {
    if ($services -contains $required) { Add-Check "service_$required" 'PASS' 'Service is running.' }
    else { Add-Check "service_$required" 'FAIL' 'Required service is not running.' }
}

if ($composeText.Contains('CONFIG_PATH: /app/librechat.yaml') -and
    $composeText.Contains('target: /app/librechat.yaml') -and
    $composeText.Contains('ENDPOINTS:') -and
    $composeText.Contains('127.0.0.1:3080:3080')) {
    Add-Check 'server_side_config' 'PASS' 'Custom endpoint configuration is wired server-side and Web is bound only to localhost.'
} else {
    Add-Check 'server_side_config' 'FAIL' 'Server-side custom endpoint wiring or localhost-only Web binding is incomplete.'
}

if ($envText -match '(?m)^ENDPOINTS\s*=\s*custom\s*$') {
    Add-Check 'endpoint_allowlist' 'PASS' 'Only the custom endpoint family is enabled.'
} else {
    Add-Check 'endpoint_allowlist' 'FAIL' 'ENDPOINTS is not restricted to custom.'
}

if ($envText -match '(?m)^AGENTOS_DEFAULT_LOCALE\s*=\s*zh-Hans\s*$') {
    Add-Check 'default_locale' 'PASS' 'The default server locale is configured as zh-Hans.'
} else {
    Add-Check 'default_locale' 'FAIL' 'AGENTOS_DEFAULT_LOCALE is not configured as zh-Hans.'
}

if ($configText.Contains('customWelcome:') -and $configText.Contains('mcpServers: {}')) {
    Add-Check 'generated_config' 'PASS' 'Generated config contains the branded interface and disabled MCP surface.'
} else {
    Add-Check 'generated_config' 'FAIL' 'Generated config is missing required V0.2 interface fields.'
}

if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -match '^__.*__$' -or -not $configText.Contains($apiKey)) {
    Add-Check 'generated_config_secret' 'PASS' 'The configured API key is not present in generated config text.'
} else {
    Add-Check 'generated_config_secret' 'FAIL' 'The configured API key is present in generated config text.'
}

$health = Check-Http -Name 'health' -Uri 'http://localhost:3080/health' -ExpectedBody 'OK'
$ready = Check-Http -Name 'ready' -Uri 'http://localhost:3080/readyz' -ExpectedBody 'OK'
$startupHtml = Check-Http -Name 'startup_html' -Uri 'http://localhost:3080/'
if ($startupHtml) {
    $hasBrandTitle = $startupHtml.Content -match ('<title>' + [regex]::Escape($brandName) + '</title>')
    $hasBrandLocale = $startupHtml.Content -match '<html\s+lang="zh-Hans">'
    $hasBrandDescription = $startupHtml.Content -match [regex]::Escape($brandDescription)
    if ($hasBrandTitle -and $hasBrandLocale -and $hasBrandDescription -and $startupHtml.Content -notmatch '<title>LibreChat</title>') {
        Add-Check 'startup_html_brand' 'PASS' 'The first HTML response uses the company title, locale and description.'
    } else {
        Add-Check 'startup_html_brand' 'FAIL' 'The first HTML response still contains incomplete default branding.'
    }
}
$languageResponse = Check-Http -Name 'login_locale_endpoint' -Uri 'http://localhost:3080/login' -Headers @{ 'Accept-Language' = '' }
if ($languageResponse -and $languageResponse.Content -match '<html\s+lang="zh-Hans"') {
    Add-Check 'default_locale_response' 'PASS' 'A request without a language header receives the zh-Hans document locale.'
} elseif ($languageResponse) {
    Add-Check 'default_locale_response' 'FAIL' 'The login document did not use the configured zh-Hans fallback locale.'
}
$configResponse = Check-Http -Name 'startup_config' -Uri 'http://localhost:3080/api/config'
if ($configResponse) {
    try {
        $startup = $configResponse.Content | ConvertFrom-Json
        if ($startup.appTitle -eq $brandName -and $startup.emailLoginEnabled -eq $true -and $startup.socialLoginEnabled -eq $false) {
            Add-Check 'startup_brand' 'PASS' 'Startup config exposes the expected company title and login policy.'
        } else {
            Add-Check 'startup_brand' 'FAIL' 'Startup config does not match the expected company branding or login policy.'
        }
        if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -match '^__.*__$' -or -not $configResponse.Content.Contains($apiKey)) {
            Add-Check 'startup_secret' 'PASS' 'The anonymous startup payload does not contain the API key.'
        } else {
            Add-Check 'startup_secret' 'FAIL' 'The anonymous startup payload contains the API key.'
        }
    } catch {
        Add-Check 'startup_brand' 'FAIL' 'The startup config is not valid JSON.'
    }
}

foreach ($asset in @('logo.svg', 'favicon-32x32.png')) {
    $assetResponse = Check-Http -Name "asset_$($asset.Replace('.', '_'))" -Uri "http://localhost:3080/assets/$asset"
    if ($assetResponse -and $asset -eq 'logo.svg' -and
        (-not $assetResponse.Content.Contains('Agent OS') -or -not $assetResponse.Content.Contains('data:image/png;base64,'))) {
        Add-Check 'logo_content' 'FAIL' 'The served logo does not contain the expected brand marker and embedded source image.'
    }
}

$hasFailure = @($checks | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$report = [ordered]@{
    schema_version = 'agentos.v0.2.local-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    checks = $checks
    gate = if ($hasFailure) { 'FAIL' } else { 'PASS' }
}
$reportParent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $reportParent)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

Write-Host "V0.2 local runtime gate: $($report.gate). Report: $ReportPath"
if ($hasFailure) { exit 1 }
exit 0
