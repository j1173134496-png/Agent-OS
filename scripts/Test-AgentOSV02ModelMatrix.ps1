[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath,
    [int]$TimeoutSec = 120,
    [ValidateRange(1, 5)][int]$RetryCount = 3,
    [ValidateRange(0, 10)][int]$RetryDelaySec = 2
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $root 'deployment\runtime\v0.2\model-matrix.json' }

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

function Get-ModelList {
    param([hashtable]$Values, [string]$Name, [string]$Fallback = '')
    $raw = Get-Value -Values $Values -Name $Name -Default $Fallback
    $models = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $raw -split '[,;]') {
        $model = $item.Trim().Trim('''"')
        if ($model -and -not $models.Contains($model)) { $models.Add($model) }
    }
    return @($models)
}

function Test-Present {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '^__.*__$'
}

function Sanitize-Text {
    param([AllowNull()][object]$Value)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if (Test-Present $apiKey) { $text = $text.Replace($apiKey, '[REDACTED]') }
    $text = [regex]::Replace($text, '(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+', '$1[REDACTED]')
    if ($text.Length -gt 500) { $text = $text.Substring(0, 500) }
    return $text
}

function Invoke-RelayJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [AllowNull()][object]$Body
    )

        for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
            try {
                $params = @{
                    Method = $Method
                    Uri = "$($baseUrl.TrimEnd('/'))/$($Path.TrimStart('/'))"
                    Headers = @{ Authorization = "Bearer $apiKey" }
                    UseBasicParsing = $true
                    TimeoutSec = $TimeoutSec
                }
                if ($null -ne $Body) {
                    $params.ContentType = 'application/json'
                    $params.Body = $Body | ConvertTo-Json -Depth 30 -Compress
                }
                $response = Invoke-WebRequest @params
                $parsed = $response.Content | ConvertFrom-Json
                return [pscustomobject]@{ ok = $true; status = [int]$response.StatusCode; body = $parsed; detail = '' }
            } catch {
                $status = 0
                $responseText = ''
                if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
                if ($_.Exception.Response) {
                    try {
                        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                        $responseText = $reader.ReadToEnd()
                        $reader.Dispose()
                    } catch {
                        $responseText = ''
                    }
                }
                $detail = (Sanitize-Text $_.Exception.Message)
                if ($responseText) {
                    try {
                        $errorPayload = $responseText | ConvertFrom-Json
                        if ($errorPayload.error.message) { $detail = Sanitize-Text $errorPayload.error.message }
                    } catch {
                        $detail = Sanitize-Text $responseText
                    }
                }
                if ($status -in @(429, 502, 503, 504) -and $attempt -lt $RetryCount) {
                    if ($RetryDelaySec -gt 0) { Start-Sleep -Seconds $RetryDelaySec }
                    continue
                }
                return [pscustomobject]@{ ok = $false; status = $status; body = $null; detail = $detail }
            }
        }
}

function Add-Result {
    param([string]$Name, [string]$Model, [string]$Status, [string]$Detail)
    $results.Add([ordered]@{ name = $Name; model = $Model; status = $Status; detail = $Detail })
}

if (-not (Test-Path -LiteralPath $EnvPath)) { throw "Missing private environment file: $EnvPath" }
$envValues = Read-DotEnv -Path $EnvPath
$baseUrl = Get-Value -Values $envValues -Name 'AGENTOS_LLM_BASE_URL'
$apiKey = Get-Value -Values $envValues -Name 'AGENTOS_LLM_API_KEY'
$defaultTextModel = Get-Value -Values $envValues -Name 'AGENTOS_LLM_MODEL'
$textModels = Get-ModelList -Values $envValues -Name 'AGENTOS_LLM_MODELS' -Fallback $defaultTextModel
$defaultImageModel = Get-Value -Values $envValues -Name 'AGENTOS_IMAGE_MODEL' -Default 'gpt-image-2'
$imageModels = Get-ModelList -Values $envValues -Name 'AGENTOS_IMAGE_MODELS' -Fallback $defaultImageModel
$protocol = (Get-Value -Values $envValues -Name 'AGENTOS_LLM_PROTOCOL' -Default 'chat_completions').ToLowerInvariant()
$results = [System.Collections.Generic.List[object]]::new()

$report = [ordered]@{
    schema_version = 'agentos.v0.2.model-matrix.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    protocol = $protocol
    default_text_model = $defaultTextModel
    text_models = @($textModels)
    default_image_model = $defaultImageModel
    image_models = @($imageModels)
    retry_policy = [ordered]@{
        retry_statuses = @(429, 502, 503, 504)
        max_attempts = $RetryCount
        delay_seconds = $RetryDelaySec
    }
    results = $results
    gate = 'BLOCKED'
}

$configurationReady = (Test-Present $baseUrl) -and (Test-Present $apiKey) -and
    (Test-Present $defaultTextModel) -and ($textModels.Count -gt 0) -and
    (Test-Present $defaultImageModel) -and ($imageModels.Count -gt 0)

if (-not $configurationReady) {
    Add-Result -Name 'configuration' -Model '' -Status 'BLOCKED' -Detail 'Set the relay URL, API key, text model list, and image model list in the private .env.'
} elseif ($protocol -ne 'chat_completions') {
    Add-Result -Name 'configuration' -Model '' -Status 'FAIL' -Detail "Model matrix currently requires AGENTOS_LLM_PROTOCOL=chat_completions; found $protocol."
} else {
    $modelResponse = Invoke-RelayJson -Method GET -Path 'v1/models'
    if (-not $modelResponse.ok) {
        Add-Result -Name 'model_catalog' -Model '' -Status 'FAIL' -Detail $modelResponse.detail
    } else {
        $availableModels = @($modelResponse.body.data | ForEach-Object { [string]$_.id } | Where-Object { $_ })
        $expectedModels = @($textModels) + @($imageModels)
        $missingModels = @($expectedModels | Where-Object { $availableModels -notcontains $_ })
        if ($missingModels.Count -gt 0) {
            Add-Result -Name 'model_catalog' -Model '' -Status 'FAIL' -Detail ('Missing configured models: ' + ($missingModels -join ', '))
        } else {
            Add-Result -Name 'model_catalog' -Model '' -Status 'PASS' -Detail ("available_models=$($availableModels.Count)")
        }
    }

    foreach ($textModel in $textModels) {
        $body = [ordered]@{
            model = $textModel
            messages = @([ordered]@{ role = 'user'; content = 'Reply with exactly MODEL_MATRIX_OK.' })
            stream = $false
        }
        $response = Invoke-RelayJson -Method POST -Path 'v1/chat/completions' -Body $body
        if (-not $response.ok) {
            Add-Result -Name 'text_completion' -Model $textModel -Status 'FAIL' -Detail $response.detail
        } elseif ([string]::IsNullOrWhiteSpace([string]$response.body.choices[0].message.content)) {
            Add-Result -Name 'text_completion' -Model $textModel -Status 'FAIL' -Detail 'The relay returned no assistant text.'
        } else {
            Add-Result -Name 'text_completion' -Model $textModel -Status 'PASS' -Detail 'assistant_text_received=true'
        }
    }

    foreach ($imageModel in $imageModels) {
        $body = [ordered]@{
            model = $imageModel
            prompt = 'A clean orange and white abstract geometric mark on a plain white background.'
            n = 1
            size = '1024x1024'
        }
        $response = Invoke-RelayJson -Method POST -Path 'v1/images/generations' -Body $body
        if (-not $response.ok) {
            # The relay currently exposes this policy failure as HTTP 403. Keep it
            # separate from a broken request so the release evidence names the
            # external group permission that must be changed.
            if ($response.status -eq 403) {
                $permissionDetail = if ($response.detail -match '(?i)image generation.*not enabled|not enabled.*image|image.*permission') {
                    $response.detail
                } else {
                    'The image generation endpoint returned HTTP 403; verify the API key group image permission and endpoint authorization.'
                }
                Add-Result -Name 'image_generation' -Model $imageModel -Status 'BLOCKED' -Detail $permissionDetail
            } else {
                Add-Result -Name 'image_generation' -Model $imageModel -Status 'FAIL' -Detail $response.detail
            }
        } elseif (@($response.body.data).Count -eq 0) {
            Add-Result -Name 'image_generation' -Model $imageModel -Status 'FAIL' -Detail 'The relay returned no image data.'
        } elseif ([string]::IsNullOrWhiteSpace([string]$response.body.data[0].b64_json) -and
            [string]::IsNullOrWhiteSpace([string]$response.body.data[0].url)) {
            Add-Result -Name 'image_generation' -Model $imageModel -Status 'FAIL' -Detail 'The relay returned neither b64_json nor url image data.'
        } else {
            $format = if ($response.body.data[0].b64_json) { 'b64_json' } else { 'url' }
            Add-Result -Name 'image_generation' -Model $imageModel -Status 'PASS' -Detail "image_data=$format"
        }
    }
}

$report.results = $results
$hasFailure = @($results | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$hasBlocked = @($results | Where-Object { $_.status -eq 'BLOCKED' }).Count -gt 0
if ($hasFailure) { $report.gate = 'FAIL' }
elseif ($hasBlocked) { $report.gate = 'BLOCKED' }
else { $report.gate = 'PASS' }

$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

Write-Host "V0.2 model matrix gate: $($report.gate). Report: $ReportPath"
if ($report.gate -eq 'FAIL') { exit 1 }
if ($report.gate -eq 'BLOCKED') { exit 2 }
exit 0
