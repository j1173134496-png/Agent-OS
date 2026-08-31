[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$OutputPath,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $root 'deployment\librechat.yaml' }

if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw "Missing private environment file: $EnvPath"
}

function Read-DotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $key = $matches[1]
            $value = $matches[2]
            if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$key] = $value
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

function Test-RelayBaseUrl {
    param([string]$Value)
    try {
        $uri = [System.Uri]$Value
        return $uri.IsAbsoluteUri -and $uri.Scheme -in @('http', 'https') -and [string]::IsNullOrWhiteSpace($uri.UserInfo)
    } catch {
        return $false
    }
}

function ConvertTo-YamlString {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '""' }
    return ($Value | ConvertTo-Json -Compress)
}

function Get-ModelList {
    param(
        [hashtable]$Values,
        [string]$Name,
        [string]$Fallback = ''
    )

    $raw = Get-Value -Values $Values -Name $Name -Default $Fallback
    $models = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $raw -split '[,;]') {
        $modelName = $item.Trim().Trim('''"')
        if ($modelName -and -not $models.Contains($modelName)) {
            $models.Add($modelName)
        }
    }
    return @($models)
}

function Test-ModelIdentifier {
    param([string]$Value)
    return $Value -match '^[A-Za-z0-9][A-Za-z0-9._:-]*$'
}

$values = Read-DotEnv -Path $EnvPath
$baseUrl = Get-Value -Values $values -Name 'AGENTOS_LLM_BASE_URL'
$apiKey = Get-Value -Values $values -Name 'AGENTOS_LLM_API_KEY'
$model = Get-Value -Values $values -Name 'AGENTOS_LLM_MODEL'
$textModels = Get-ModelList -Values $values -Name 'AGENTOS_LLM_MODELS' -Fallback $model
$imageDefaultModel = Get-Value -Values $values -Name 'AGENTOS_IMAGE_MODEL' -Default 'gpt-image-2'
$imageModels = Get-ModelList -Values $values -Name 'AGENTOS_IMAGE_MODELS' -Fallback $imageDefaultModel
$protocol = (Get-Value -Values $values -Name 'AGENTOS_LLM_PROTOCOL' -Default 'chat_completions').ToLowerInvariant()
$locale = Get-Value -Values $values -Name 'AGENTOS_DEFAULT_LOCALE' -Default 'zh-Hans'

if ($protocol -notin @('chat_completions', 'responses')) {
    throw 'AGENTOS_LLM_PROTOCOL must be chat_completions or responses.'
}
if (-not (Test-Present $locale)) { $locale = 'zh-Hans' }

foreach ($configuredModel in (@($textModels) + @($imageModels))) {
    if ((Test-Present $configuredModel) -and -not (Test-ModelIdentifier $configuredModel)) {
        throw "Invalid model identifier: $configuredModel"
    }
}
if ((Test-Present $model) -and ($textModels -notcontains $model)) {
    throw 'AGENTOS_LLM_MODEL must be included in AGENTOS_LLM_MODELS.'
}
if ((Test-Present $imageDefaultModel) -and ($imageModels -notcontains $imageDefaultModel)) {
    throw 'AGENTOS_IMAGE_MODEL must be included in AGENTOS_IMAGE_MODELS.'
}

$configured = (Test-Present $baseUrl) -and (Test-Present $apiKey) -and (Test-Present $model) -and ($textModels.Count -gt 0)
$brandName = (-join ([char[]](0x7ACB, 0x80FD, 0x6D3E))) + ' Agent OS'
$relayName = (-join ([char[]](0x7ACB, 0x80FD, 0x6D3E, 0x4E2D, 0x8F6C)))
$relayDescription = $brandName + ' ' + (-join ([char[]](0x4E2D, 0x8F6C, 0x6A21, 0x578B)))
$baseUrlSuffix = if ($baseUrl.TrimEnd('/') -match '/v1$') { '' } else { '/v1' }
if ((Test-Present $baseUrl) -and -not (Test-RelayBaseUrl $baseUrl)) {
    throw 'AGENTOS_LLM_BASE_URL must be an absolute http(s) URL without embedded user info.'
}
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('version: 1.3.13')
$lines.Add('cache: true')
$lines.Add('interface:')
# Keep the generated script ASCII-safe for Windows PowerShell 5.1. YAML decodes these Unicode escapes.
$lines.Add('  customWelcome: "\u6B22\u8FCE\u4F7F\u7528 \u7ACB\u80FD\u6D3E Agent OS\u3002\u8BF7\u9009\u62E9\u5DF2\u914D\u7F6E\u7684\u516C\u53F8\u6A21\u578B\u5F00\u59CB\u5BF9\u8BDD\u3002"')
$lines.Add('  modelSelect: true')
$lines.Add('  parameters: false')
$lines.Add('  presets: false')
$lines.Add('  agents: true')
$lines.Add('  mcpServers: {}')
$lines.Add('  prompts: false')
$lines.Add('endpoints:')

if ($configured) {
    $lines.Add('  custom:')
    $lines.Add("    - name: $relayName")
    $lines.Add('      apiKey: ' + [char]39 + '${AGENTOS_LLM_API_KEY}' + [char]39)
    $lines.Add("      baseURL: '$('${AGENTOS_LLM_BASE_URL}')$baseUrlSuffix'")
    $lines.Add('      models:')
    $lines.Add('        default:')
    foreach ($textModel in $textModels) {
        $lines.Add("          - $(ConvertTo-YamlString $textModel)")
    }
    $lines.Add('        fetch: false')
    $lines.Add('      iconURL: /assets/logo-mark.png')
    $lines.Add("      modelDisplayLabel: $relayName")
    $lines.Add('      titleConvo: false')
    $lines.Add('      customParams:')
    $lines.Add('        defaultParamsEndpoint: openAI')
    $lines.Add('  agents:')
    $lines.Add('    allowedProviders:')
    $lines.Add("      - $(ConvertTo-YamlString $relayName)")
    $lines.Add('modelSpecs:')
    $lines.Add('  prioritize: true')
    $lines.Add('  enforce: true')
    $lines.Add('  list:')
    for ($index = 0; $index -lt $textModels.Count; $index++) {
        $textModel = $textModels[$index]
        $specName = 'agentos-' + (($textModel -replace '[^A-Za-z0-9]+', '-') -replace '^-|-$', '')
        $lines.Add("    - name: $specName")
        $lines.Add("      label: $(ConvertTo-YamlString $textModel)")
        $lines.Add("      default: $(if ($index -eq 0) { 'true' } else { 'false' })")
        $lines.Add('      showOnLanding: true')
        $lines.Add("      description: $(ConvertTo-YamlString ($relayDescription + ' - ' + $textModel))")
        $lines.Add('      iconURL: /assets/logo-mark.png')
        $lines.Add('      preset:')
        $lines.Add("        endpoint: $relayName")
        $lines.Add("        model: $(ConvertTo-YamlString $textModel)")
        $lines.Add('        stream: true')
        if ($protocol -eq 'responses') { $lines.Add('        useResponsesApi: true') }
    }
    for ($index = 0; $index -lt $textModels.Count; $index++) {
        $textModel = $textModels[$index]
        $agentSpecName = 'agentos-agent-' + (($textModel -replace '[^A-Za-z0-9]+', '-') -replace '^-|-$', '')
        $lines.Add("    - name: $agentSpecName")
        $lines.Add("      label: $(ConvertTo-YamlString ($textModel + ' Agent'))")
        $lines.Add('      default: false')
        $lines.Add('      showOnLanding: false')
        $lines.Add("      description: $(ConvertTo-YamlString ($brandName + ' Agent - ' + $textModel))")
        $lines.Add('      iconURL: /assets/logo-mark.png')
        $lines.Add('      preset:')
        # AgentOS uses the agents route with an ephemeral agent backed by the configured relay.
        $lines.Add("        endpoint: $relayName")
        $lines.Add("        model: $(ConvertTo-YamlString $textModel)")
        $lines.Add('        stream: true')
        if ($protocol -eq 'responses') { $lines.Add('        useResponsesApi: true') }
    }
} else {
    $lines.Add('  custom: []')
}

$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllLines($OutputPath, $lines, [System.Text.UTF8Encoding]::new($false))

if (-not $Quiet) {
    $state = if ($configured) { 'configured' } else { 'BLOCKED: relay parameters missing' }
    Write-Host "V0.2 config synchronized ($state, protocol=$protocol, locale=$locale): $OutputPath"
}
