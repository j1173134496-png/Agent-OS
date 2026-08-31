[CmdletBinding()]
param(
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.1\branding-report.json'
}
$checks = [System.Collections.Generic.List[object]]::new()

function Assert-Check {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    $status = if ($Condition) { 'PASS' } else { 'FAIL' }
    $checks.Add([ordered]@{ name = $Name; status = $status; detail = $Detail })
}

function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText((Join-Path $root $Path))
}

$sourceTheme = Read-Text 'source\librechat-maintained\client\src\agentos-theme.css'
$rollbackTheme = Read-Text 'deployment\rollback\v0.3.0\branding\agentos-theme.css'
$rollbackScript = Read-Text 'deployment\rollback\v0.3.0\branding\agentos-plugins.js'

foreach ($theme in @(
        [pscustomobject]@{ Name = 'source_theme'; Text = $sourceTheme },
        [pscustomobject]@{ Name = 'rollback_theme'; Text = $rollbackTheme }
    )) {
    Assert-Check (
        $theme.Text -notmatch 'img\[src\*=''image_gen_oai''\]' -and
        $theme.Text -notmatch 'img\[src\*="image_gen_oai"\]'
    ) "$($theme.Name)_no_generation_substring_selector" 'Generation filenames are not selected by a broad CSS substring rule.'
    Assert-Check (
        $theme.Text -match "/assets/image_gen_oai\."
    ) "$($theme.Name)_asset_boundary" 'The image tool icon remains brandable only under /assets/. '
    Assert-Check (
        $theme.Text -notmatch "img\[alt\*="
    ) "$($theme.Name)_no_global_alt_selector" 'Global alt-text matching cannot rewrite message images.'
}

Assert-Check (
    $rollbackScript -match 'function isBrandAssetSource' -and
    $rollbackScript.Contains("parsed.pathname.indexOf('/assets/')") -and
    $rollbackScript -notmatch 'DEFAULT_ICON_PATTERN'
) 'rollback_script_asset_boundary' 'Rollback branding script limits replacement to same-origin /assets/ icon files.'

$assetNamePattern = '^(openai|anthropic|claude|google|gemini|azure|mistral|meta|deepseek|qwen|ollama|image_gen_oai|image_edit_oai)([._-].*)?$'
foreach ($case in @(
        [pscustomobject]@{ Source = '/assets/openai.svg'; Expected = $true },
        [pscustomobject]@{ Source = '/assets/image_gen_oai.png'; Expected = $true },
        [pscustomobject]@{ Source = '/images/user/image_gen_oai-123.png'; Expected = $false },
        [pscustomobject]@{ Source = '/api/share/image_gen_oai.png'; Expected = $false },
        [pscustomobject]@{ Source = 'data:image/png;base64,abc'; Expected = $false },
        [pscustomobject]@{ Source = 'blob:http://localhost/image_gen_oai'; Expected = $false }
    )) {
    $uri = [Uri]::new([Uri]::new('http://localhost:3080'), $case.Source)
    $filename = [IO.Path]::GetFileName($uri.AbsolutePath)
    $actual = $uri.AbsolutePath.Contains('/assets/') -and $filename -match $assetNamePattern
    Assert-Check ($actual -eq $case.Expected) "path_$($case.Source.Replace('/', '_').Replace(':', '_').Replace('.', '_'))" "Expected $($case.Expected) for $($case.Source)."
}

$failed = @($checks | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$report = [ordered]@{
    schema_version = 'agentos.v0.3.1.branding-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    checks = $checks
    gate = if ($failed) { 'FAIL' } else { 'PASS' }
}
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
$checks | ForEach-Object { "[$($_.status)] $($_.name): $($_.detail)" }
if ($failed) {
    Write-Error 'AgentOS branding regression gate: FAIL'
    exit 1
}
Write-Host 'AgentOS branding regression gate: PASS'
exit 0
