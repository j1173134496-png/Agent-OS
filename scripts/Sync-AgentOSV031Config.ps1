[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$OutputPath,
    [string]$ReasoningMatrixPath,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $root 'deployment\librechat.yaml' }
if ([string]::IsNullOrWhiteSpace($ReasoningMatrixPath)) {
    $ReasoningMatrixPath = Join-Path $root 'deployment\agentos-reasoning-matrix.json'
}

if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw "Missing private environment file: $EnvPath"
}

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
    param([hashtable]$Values, [string]$Name, [string]$Default = '')
    if ($Values.ContainsKey($Name)) { return [string]$Values[$Name] }
    return $Default
}

function Test-Present {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '^__.*__$'
}

function ConvertTo-YamlString {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '""' }
    return ($Value | ConvertTo-Json -Compress)
}

function Get-ModelList {
    param([hashtable]$Values, [string]$Name, [string]$Fallback = '')
    $raw = Get-Value -Values $Values -Name $Name -Default $Fallback
    $models = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $raw -split '[,;]') {
        $modelName = $item.Trim().Trim('''"')
        if ($modelName -and -not $models.Contains($modelName)) { $models.Add($modelName) }
    }
    return @($models)
}

function Test-ModelIdentifier {
    param([string]$Value)
    return $Value -match '^[A-Za-z0-9][A-Za-z0-9._:-]*$'
}

function Get-VerifiedLevels {
    param([AllowNull()][object]$Matrix, [string]$Model)
    if ($null -eq $Matrix -or $Matrix.gate -ne 'PASS') { return @() }
    $entry = @($Matrix.models | Where-Object { [string]$_.model -eq $Model }) | Select-Object -First 1
    if ($null -eq $entry) { return @() }
    return @($entry.levels | Where-Object { $_.status -eq 'PASS' } | ForEach-Object { [string]$_.value })
}

$values = Read-DotEnv -Path $EnvPath
$baseUrl = Get-Value -Values $values -Name 'AGENTOS_LLM_BASE_URL'
$apiKey = Get-Value -Values $values -Name 'AGENTOS_LLM_API_KEY'
$model = Get-Value -Values $values -Name 'AGENTOS_LLM_MODEL' -Default 'gpt-5.5'
$configuredModels = Get-ModelList -Values $values -Name 'AGENTOS_LLM_MODELS' -Fallback $model
$imageDefaultModel = Get-Value -Values $values -Name 'AGENTOS_IMAGE_MODEL' -Default 'gpt-image-2'
$imageModels = Get-ModelList -Values $values -Name 'AGENTOS_IMAGE_MODELS' -Fallback $imageDefaultModel

# This is the V0.3.1 employee-facing product whitelist. Runtime/provider details stay server-side.
$approvedTextModels = @('gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5')
$displayLabels = @{
    'gpt-5.6-sol' = 'GPT-5.6 Sol'
    'gpt-5.6-terra' = 'GPT-5.6 Terra'
    'gpt-5.6-luna' = 'GPT-5.6 Luna'
    'gpt-5.5' = 'GPT-5.5'
}
if ($configuredModels.Count -ne $approvedTextModels.Count -or @($configuredModels | Where-Object { $_ -notin $approvedTextModels }).Count -gt 0 -or @($approvedTextModels | Where-Object { $_ -notin $configuredModels }).Count -gt 0) {
    throw 'AGENTOS_LLM_MODELS must contain exactly the approved V0.3.1 models: gpt-5.6-sol,gpt-5.6-terra,gpt-5.6-luna,gpt-5.5.'
}
$textModels = $approvedTextModels

if ($textModels -notcontains $model) { throw 'AGENTOS_LLM_MODEL must be one of the approved V0.3.1 models.' }
foreach ($configuredModel in (@($textModels) + @($imageModels))) {
    if ((Test-Present $configuredModel) -and -not (Test-ModelIdentifier $configuredModel)) {
        throw "Invalid model identifier: $configuredModel"
    }
}
if ((Test-Present $imageDefaultModel) -and ($imageModels -notcontains $imageDefaultModel)) {
    throw 'AGENTOS_IMAGE_MODEL must be included in AGENTOS_IMAGE_MODELS.'
}

$configured = (Test-Present $baseUrl) -and (Test-Present $apiKey)
$brandName = (-join ([char[]](0x7ACB, 0x80FD, 0x6D3E))) + ' Agent OS'
$relayName = (-join ([char[]](0x7ACB, 0x80FD, 0x6D3E, 0x4E2D, 0x8F6C)))
$baseUrlSuffix = if ($baseUrl.TrimEnd('/') -match '/v1$') { '' } else { '/v1' }
if ((Test-Present $baseUrl)) {
    try {
        $uri = [System.Uri]$baseUrl
        if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http', 'https') -or -not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
            throw 'invalid URL'
        }
    } catch {
        throw 'AGENTOS_LLM_BASE_URL must be an absolute http(s) URL without embedded user info.'
    }
}

$matrix = $null
if (Test-Path -LiteralPath $ReasoningMatrixPath) {
    $matrix = Get-Content -LiteralPath $ReasoningMatrixPath -Raw | ConvertFrom-Json
    if ($matrix.schema_version -ne 'agentos.v0.3.1.reasoning-matrix.v1') {
        throw "Unsupported reasoning matrix schema: $($matrix.schema_version)"
    }
}
$reasoningEnabled = $null -ne $matrix -and $matrix.gate -eq 'PASS'
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('version: 1.3.13')
$lines.Add('cache: true')
$lines.Add('interface:')
$lines.Add('  customWelcome: "\u6B22\u8FCE\u4F7F\u7528 \u7ACB\u80FD\u6D3E Agent OS\u3002\u8BF7\u9009\u62E9\u5DF2\u914D\u7F6E\u7684\u516C\u53F8\u6A21\u578B\u5F00\u59CB\u5BF9\u8BDD\u3002"')
$lines.Add('  modelSelect: true')
$lines.Add('  parameters: false')
$lines.Add('  presets: false')
$lines.Add('  agents: true')
$lines.Add('  mcpServers: {}')
$lines.Add('  prompts: false')
$lines.Add('  defaultPinnedTools:')
$lines.Add('    - image_gen_oai')
$lines.Add('  agentosReasoning:')
$lines.Add("    enabled: $(if ($reasoningEnabled) { 'true' } else { 'false' })")
$lines.Add('    default: medium')
$lines.Add('    levels:')
foreach ($level in @('low', 'medium', 'high')) { $lines.Add("      - $level") }
$lines.Add('    models:')
foreach ($textModel in $textModels) {
    $lines.Add("      $textModel`:")
    $lines.Add('        levels:')
    foreach ($level in (Get-VerifiedLevels -Matrix $matrix -Model $textModel)) { $lines.Add("          - $level") }
}
$lines.Add('endpoints:')

if ($configured) {
    $lines.Add('  custom:')
    $lines.Add("    - name: $relayName")
    $lines.Add('      apiKey: ' + [char]39 + '${AGENTOS_LLM_API_KEY}' + [char]39)
    $lines.Add("      baseURL: '$('${AGENTOS_LLM_BASE_URL}')$baseUrlSuffix'")
    $lines.Add('      models:')
    $lines.Add('        default:')
    foreach ($textModel in $textModels) { $lines.Add("          - $(ConvertTo-YamlString $textModel)") }
    $lines.Add('        fetch: false')
    $lines.Add('      iconURL: /assets/logo-mark.png')
    $lines.Add("      modelDisplayLabel: $relayName")
    $lines.Add('      titleConvo: false')
    $lines.Add('      customParams:')
    $lines.Add('        defaultParamsEndpoint: openAI')
    $lines.Add('  agents:')
    $lines.Add('    allowedProviders:')
    $lines.Add("      - $(ConvertTo-YamlString $relayName)")
    $lines.Add('    capabilities:')
    foreach ($capability in @('tools', 'skills', 'web_search', 'file_search', 'execute_code', 'actions')) {
        $lines.Add("      - $capability")
    }
} else {
    $lines.Add('  custom: []')
}

$lines.Add('modelSpecs:')
$lines.Add('  prioritize: true')
$lines.Add('  enforce: true')
$lines.Add('  addedEndpoints:')
$lines.Add('    - agents')
$lines.Add('  list:')
foreach ($textModel in $textModels) {
    $specName = 'agentos-' + (($textModel -replace '[^A-Za-z0-9]+', '-') -replace '^-|-$', '')
    $lines.Add("    - name: $specName")
    $lines.Add("      label: $(ConvertTo-YamlString $displayLabels[$textModel])")
    $lines.Add("      default: $(if ($textModel -eq $model) { 'true' } else { 'false' })")
    $lines.Add('      showOnLanding: true')
    $lines.Add('      description: "\u4F01\u4E1A\u6587\u672C\u6A21\u578B"')
    $lines.Add('      iconURL: /assets/logo-mark.png')
    $lines.Add('      preset:')
    $lines.Add("        endpoint: $relayName")
    $lines.Add("        model: $(ConvertTo-YamlString $textModel)")
    $lines.Add('        stream: true')
}

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllLines($OutputPath, $lines, [System.Text.UTF8Encoding]::new($false))

if (-not $Quiet) {
    $state = if ($configured) { 'configured' } else { 'BLOCKED: relay parameters missing' }
    $reasoningState = if ($reasoningEnabled) { 'verified' } else { 'BLOCKED: reasoning matrix missing or failed' }
    Write-Host "V0.3.1 config synchronized ($state, reasoning=$reasoningState): $OutputPath"
}
