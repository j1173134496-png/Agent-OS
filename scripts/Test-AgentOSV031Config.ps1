[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.1\config-report.json'
}
$brandTitle = [string]::Concat(([char]0x7ACB).ToString(), ([char]0x80FD).ToString(), ([char]0x6D3E).ToString(), ' Agent OS')

$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    $status = if ($Condition) { 'PASS' } else { 'FAIL' }
    $checks.Add([ordered]@{ name = $Name; status = $status; detail = $Detail })
}

function Read-DotEnv {
    param([string]$Path)
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

if (-not (Test-Path -LiteralPath $EnvPath)) { throw "Missing private environment file: $EnvPath" }
$envValues = Read-DotEnv -Path $EnvPath
$configuredModels = [string]$envValues['AGENTOS_LLM_MODELS']
$expectedModels = 'gpt-5.6-sol,gpt-5.6-terra,gpt-5.6-luna,gpt-5.5'
$configPath = Join-Path $root 'deployment\librechat.yaml'
$configText = if (Test-Path -LiteralPath $configPath) { [IO.File]::ReadAllText($configPath) } else { '' }
$composePath = Join-Path $root 'deployment\compose.yaml'
$composeText = if (Test-Path -LiteralPath $composePath) { [IO.File]::ReadAllText($composePath) } else { '' }
$interfaceSourcePath = Join-Path $root 'source\librechat-maintained\packages\data-schemas\src\app\interface.ts'
$interfaceSourceText = if (Test-Path -LiteralPath $interfaceSourcePath) { [IO.File]::ReadAllText($interfaceSourcePath) } else { '' }
$indexPath = Join-Path $root 'source\librechat-maintained\client\index.html'
$indexText = if (Test-Path -LiteralPath $indexPath) { [IO.File]::ReadAllText($indexPath) } else { '' }
$matrixPath = Join-Path $root 'deployment\agentos-reasoning-matrix.json'
$matrix = if (Test-Path -LiteralPath $matrixPath) { Get-Content -LiteralPath $matrixPath -Raw | ConvertFrom-Json } else { $null }

Add-Check 'approved_model_environment' ($configuredModels -eq $expectedModels) 'The private environment contains exactly the four approved V0.3.1 text model IDs.'
Add-Check 'default_text_model' ([string]$envValues['AGENTOS_LLM_MODEL'] -eq 'gpt-5.5') 'The default text model is gpt-5.5.'
Add-Check 'default_image_model' ([string]$envValues['AGENTOS_IMAGE_MODEL'] -eq 'gpt-image-2') 'The default image model is gpt-image-2.'
Add-Check 'config_exists' (Test-Path -LiteralPath $configPath) 'The generated LibreChat configuration exists.'
Add-Check 'config_secret_placeholder' ($configText.Contains('${AGENTOS_LLM_API_KEY}') -and $configText -notmatch [regex]::Escape([string]$envValues['AGENTOS_LLM_API_KEY'])) 'The generated config retains a server-side API key placeholder.'
Add-Check 'model_specs_count' (@([regex]::Matches($configText, '(?m)^    - name: agentos-')).Count -eq 4) 'The employee model catalog contains exactly four model specs.'
$missingLabels = @('GPT-5.6 Sol', 'GPT-5.6 Terra', 'GPT-5.6 Luna', 'GPT-5.5') | Where-Object {
    -not $configText.Contains(('label: "' + $_ + '"'))
}
Add-Check 'model_labels' (@($missingLabels).Count -eq 0) 'All approved employee-facing labels are present.'
Add-Check 'no_agent_model_specs' ($configText -notmatch '(?im)(label:.*Agent|name:.*agentos-agent-)') 'No Agent-suffixed model spec is exposed.'
Add-Check 'no_image_model_spec' ($configText -notmatch '(?im)label:.*gpt-image|model:.*gpt-image') 'The image model is not exposed in the text model selector.'
Add-Check 'reasoning_enabled' ($configText.Contains("  agentosReasoning:`r`n    enabled: true") -and $null -ne $matrix -and $matrix.gate -eq 'PASS') 'The reasoning matrix is verified and enabled in generated config.'
Add-Check 'reasoning_runtime_contract' ($interfaceSourceText.Contains('agentosReasoning: interfaceConfig?.agentosReasoning')) 'The server preserves the reasoning contract in interfaceConfig.'
foreach ($model in @('gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5')) {
    $entry = @($matrix.models | Where-Object { $_.model -eq $model }) | Select-Object -First 1
    $levels = if ($null -ne $entry) { @($entry.supported_levels) } else { @() }
    $missingLevels = @('low', 'medium', 'high') | Where-Object { $_ -notin $levels }
    Add-Check "reasoning_$model" (@($missingLevels).Count -eq 0) "The verified matrix exposes low/medium/high for $model."
}
Add-Check 'brand_footer' ($composeText -match ('(?m)^\s+CUSTOM_FOOTER:\s+"' + [regex]::Escape($brandTitle) + '"\s*$')) 'Compose provides the AgentOS footer through LibreChat''s effective CUSTOM_FOOTER contract.'
Add-Check 'brand_theme_color' ($indexText -match 'theme-color" content="#ff6a00"') 'The source document uses the AgentOS theme color.'

$failed = @($checks | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$report = [ordered]@{
    schema_version = 'agentos.v0.3.1.config-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    checks = $checks
    gate = if ($failed) { 'FAIL' } else { 'PASS' }
}
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

Write-Host "V0.3.1 config contract: $($report.gate). Report: $ReportPath"
if ($failed) { exit 1 }
exit 0
