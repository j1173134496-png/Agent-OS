[CmdletBinding()]
param(
  [string]$EnvPath = (Join-Path $PSScriptRoot '..\.env'),
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\deployment\runtime\model-connection-report.json'),
  [int]$TimeoutSec = 30
)

$ErrorActionPreference = 'Stop'

function Read-DotEnv([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Environment file not found: $Path" }
  $values = @{}
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^\s*([^#=\s]+)\s*=\s*(.*)\s*$') {
      $value = $Matches[2].Trim()
      if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) { $value = $value.Substring(1, $value.Length - 2) }
      $values[$Matches[1]] = $value
    }
  }
  return $values
}

function Normalize-BaseUrl([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { throw 'AGENTOS_LLM_BASE_URL is empty.' }
  $uri = [Uri]$Value
  if ($uri.Scheme -notin @('http','https') -or $uri.UserInfo) { throw 'AGENTOS_LLM_BASE_URL must be an absolute http(s) URL without credentials.' }
  $path = $uri.AbsolutePath.TrimEnd('/')
  if ($path -match '/v1$') { $path = $path.Substring(0, $path.Length - 3).TrimEnd('/') }
  return ('{0}://{1}{2}' -f $uri.Scheme, $uri.Authority, $path)
}

$envValues = Read-DotEnv $EnvPath
$baseUrl = Normalize-BaseUrl ([string]$envValues['AGENTOS_LLM_BASE_URL'])
$apiKey = [string]$envValues['AGENTOS_LLM_API_KEY']
$defaultModel = [string]$envValues['AGENTOS_LLM_MODEL']
$models = @([string]$envValues['AGENTOS_LLM_MODELS'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $models -contains $defaultModel) { $models += $defaultModel }
if ([string]::IsNullOrWhiteSpace($apiKey) -or $apiKey -match '^(__REQUIRED__|changeme)$') { throw 'AGENTOS_LLM_API_KEY is not configured.' }

$headers = @{ Authorization = "Bearer $apiKey"; 'Content-Type' = 'application/json' }
$report = [ordered]@{ checked_at = (Get-Date).ToUniversalTime().ToString('o'); base_url = $baseUrl; default_model = $defaultModel; configured_models = $models; models_endpoint = $null; chat_endpoint = $null; status = 'FAIL'; errors = @() }

try {
  $modelsResponse = Invoke-RestMethod -Method Get -Uri "$baseUrl/v1/models" -Headers $headers -TimeoutSec $TimeoutSec
  $available = @($modelsResponse.data | ForEach-Object { $_.id })
  $report.models_endpoint = [ordered]@{ status = 'PASS'; available_models = $available; default_model_available = ($available -contains $defaultModel) }
  if (-not ($available -contains $defaultModel)) { throw "Default model '$defaultModel' is not advertised by the relay." }
  $body = @{ model = $defaultModel; messages = @(@{ role = 'user'; content = 'Reply with OK.' }); max_tokens = 8; temperature = 0 } | ConvertTo-Json -Depth 6
  $chat = Invoke-RestMethod -Method Post -Uri "$baseUrl/v1/chat/completions" -Headers $headers -Body $body -TimeoutSec $TimeoutSec
  $report.chat_endpoint = [ordered]@{ status = 'PASS'; model = $chat.model; response_received = ($null -ne $chat.choices) }
  $report.status = 'PASS'
} catch {
  $report.errors += $_.Exception.Message
}

$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$report | ConvertTo-Json -Depth 8
if ($report.status -ne 'PASS') { exit 1 }
