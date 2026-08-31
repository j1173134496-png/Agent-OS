[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$syncScript = Join-Path $PSScriptRoot 'Sync-AgentOSV02Config.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agentos-v02-config-' + [guid]::NewGuid().ToString('N'))
$failed = $false

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Protocol,
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [Parameter(Mandatory = $true)][string]$Model,
        [string]$BaseUrl = 'https://relay.example/v1',
        [string]$Models = '',
        [string]$ImageModel = 'gpt-image-2',
        [string]$ImageModels = 'gpt-image-1.5,gpt-image-2'
    )

    $lines = @(
        "AGENTOS_LLM_BASE_URL=$BaseUrl",
        "AGENTOS_LLM_API_KEY=$ApiKey",
        "AGENTOS_LLM_MODEL=$Model",
        "AGENTOS_LLM_MODELS=$Models",
        "AGENTOS_LLM_PROTOCOL=$Protocol",
        "AGENTOS_IMAGE_MODEL=$ImageModel",
        "AGENTOS_IMAGE_MODELS=$ImageModels",
        'AGENTOS_DEFAULT_LOCALE=zh-Hans'
    )
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $chatEnv = Join-Path $tempRoot 'chat.env'
    $chatConfig = Join-Path $tempRoot 'chat.yaml'
    Write-Fixture -Path $chatEnv -Protocol 'chat_completions' -ApiKey 'fixture-api-key' -Model 'fixture-chat-model' -Models 'fixture-chat-model,fixture-chat-model-2'
    & $syncScript -EnvPath $chatEnv -OutputPath $chatConfig -Quiet
    $chatText = [System.IO.File]::ReadAllText($chatConfig)
    Assert-True ($chatText.Contains('custom:')) 'Chat fixture did not create the custom endpoint.'
    Assert-True ($chatText.Contains('${AGENTOS_LLM_API_KEY}')) 'Chat fixture lost the server-side API key placeholder.'
    Assert-True ($chatText.Contains('${AGENTOS_LLM_BASE_URL}')) 'Chat fixture lost the server-side Base URL placeholder.'
    Assert-True ($chatText.Contains('fixture-chat-model')) 'Chat fixture did not preserve the configured model.'
    Assert-True ($chatText.Contains('fixture-chat-model-2')) 'Chat fixture did not preserve the configured model list.'
    Assert-True ($chatText.Contains('name: agentos-fixture-chat-model-2')) 'Chat fixture did not create a selectable model spec for each model.'
    Assert-True ($chatText.Contains('allowedProviders:')) 'Chat fixture did not configure the relay provider for Agents.'
    Assert-True ($chatText.Contains('name: agentos-agent-fixture-chat-model')) 'Chat fixture did not create an Agent model spec.'
    Assert-True ($chatText.Contains('agents: true')) 'Chat fixture did not enable the agent surface needed by image tools.'
    Assert-True (-not $chatText.Contains('fixture-api-key')) 'Chat fixture wrote the API key into generated config.'

    $responsesEnv = Join-Path $tempRoot 'responses.env'
    $responsesConfig = Join-Path $tempRoot 'responses.yaml'
    Write-Fixture -Path $responsesEnv -Protocol 'responses' -ApiKey 'fixture-responses-key' -Model 'fixture-responses-model' -Models 'fixture-responses-model'
    & $syncScript -EnvPath $responsesEnv -OutputPath $responsesConfig -Quiet
    $responsesText = [System.IO.File]::ReadAllText($responsesConfig)
    Assert-True ($responsesText.Contains('useResponsesApi: true')) 'Responses fixture did not enable the Responses API model parameter.'
    Assert-True (-not $responsesText.Contains('fixture-responses-key')) 'Responses fixture wrote the API key into generated config.'

    $blockedEnv = Join-Path $tempRoot 'blocked.env'
    $blockedConfig = Join-Path $tempRoot 'blocked.yaml'
    Write-Fixture -Path $blockedEnv -Protocol 'chat_completions' -ApiKey '__REQUIRED__' -Model '__REQUIRED__' -Models '__REQUIRED__'
    & $syncScript -EnvPath $blockedEnv -OutputPath $blockedConfig -Quiet
    $blockedText = [System.IO.File]::ReadAllText($blockedConfig)
    Assert-True ($blockedText.Contains('custom: []')) 'Missing-credentials fixture exposed a relay endpoint.'
    Assert-True (-not $blockedText.Contains('AGENTOS_LLM_API_KEY')) 'Missing-credentials fixture retained a credential placeholder.'

    $invalidEnv = Join-Path $tempRoot 'invalid.env'
    Write-Fixture -Path $invalidEnv -Protocol 'unsupported' -ApiKey '__REQUIRED__' -Model '__REQUIRED__'
    $invalidFailed = $false
    try {
        & $syncScript -EnvPath $invalidEnv -OutputPath (Join-Path $tempRoot 'invalid.yaml') -Quiet
    } catch {
        $invalidFailed = $true
    }
    Assert-True $invalidFailed 'Invalid protocol was accepted by the config synchronizer.'

    $invalidUrlEnv = Join-Path $tempRoot 'invalid-url.env'
    Write-Fixture -Path $invalidUrlEnv -Protocol 'chat_completions' -ApiKey 'fixture-invalid-url-key' -Model 'fixture-invalid-url-model' -BaseUrl 'ftp://relay.example/v1'
    $invalidUrlFailed = $false
    try {
        & $syncScript -EnvPath $invalidUrlEnv -OutputPath (Join-Path $tempRoot 'invalid-url.yaml') -Quiet
    } catch {
        $invalidUrlFailed = $true
    }
    Assert-True $invalidUrlFailed 'A non-HTTP(S) relay URL was accepted by the config synchronizer.'

    Write-Host 'V0.2 config contract test: PASS'
} catch {
    $failed = $true
    Write-Error $_.Exception.Message
    Write-Host 'V0.2 config contract test: FAIL'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($failed) { exit 1 }
exit 0
