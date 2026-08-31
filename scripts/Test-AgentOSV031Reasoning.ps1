[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath,
    [string]$MatrixPath,
    [int]$TimeoutSec = 45,
    [ValidateRange(1, 5)][int]$RetryCount = 4,
    [ValidateRange(0, 10)][int]$RetryDelaySec = 2
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $root 'deployment\runtime\v0.3.1\reasoning-matrix.json' }
if ([string]::IsNullOrWhiteSpace($MatrixPath)) { $MatrixPath = Join-Path $root 'deployment\agentos-reasoning-matrix.json' }

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

function Sanitize-Text {
    param([AllowNull()][object]$Value)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if (Test-Present $apiKey) { $text = $text.Replace($apiKey, '[REDACTED]') }
    $text = [regex]::Replace($text, '(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+', '$1[REDACTED]')
    $text = [regex]::Replace($text, '(?i)(api[_-]?key\s*[:=]\s*)[^\s,;]+', '$1[REDACTED]')
    if ($text.Length -gt 500) { $text = $text.Substring(0, 500) }
    return $text
}

function Join-RelayPath {
    param([string]$Path)
    $apiBaseUrl = $baseUrl.TrimEnd('/')
    if ($apiBaseUrl -notmatch '/v1$') { $apiBaseUrl += '/v1' }
    return "$apiBaseUrl/$($Path.TrimStart('/'))"
}

function Invoke-RelayJson {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][hashtable]$Body
    )
    $headers = @{ Authorization = "Bearer $apiKey"; Accept = 'application/json' }
    $bodyJson = $Body | ConvertTo-Json -Depth 20 -Compress
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            $response = Invoke-WebRequest -Method POST -Uri $Uri -Headers $headers -ContentType 'application/json' -Body $bodyJson -UseBasicParsing -TimeoutSec $TimeoutSec
            return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = ($response.Content | ConvertFrom-Json); Raw = [string]$response.Content; Error = '' }
        } catch {
            $status = 0
            $raw = ''
            if ($_.Exception.Response) {
                try { $status = [int]$_.Exception.Response.StatusCode } catch { }
                try {
                    $reader = [IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                    $raw = $reader.ReadToEnd()
                    $reader.Dispose()
                } catch { }
            }
            if ([string]::IsNullOrWhiteSpace($raw) -and $_.ErrorDetails -and $_.ErrorDetails.Message) { $raw = [string]$_.ErrorDetails.Message }
            $parsed = $null
            if (-not [string]::IsNullOrWhiteSpace($raw)) { try { $parsed = $raw | ConvertFrom-Json } catch { } }
            if ($status -in @(429, 502, 503, 504) -and $attempt -lt $RetryCount) {
                if ($RetryDelaySec -gt 0) { Start-Sleep -Seconds $RetryDelaySec }
                continue
            }
            return [pscustomobject]@{ StatusCode = $status; Body = $parsed; Raw = (Sanitize-Text $raw); Error = (Sanitize-Text $_.Exception.Message) }
        }
    }
}

function Get-ChatText {
    param([AllowNull()][object]$Body)
    if ($null -eq $Body) { return '' }
    $choices = @($Body.choices)
    if ($choices.Count -eq 0 -or $null -eq $choices[0].message) { return '' }
    return [string]$choices[0].message.content
}

function Get-ResponsesText {
    param([AllowNull()][object]$Body)
    if ($null -eq $Body) { return '' }
    $content = [string]$Body.output_text
    if ([string]::IsNullOrWhiteSpace($content) -and $Body.output) {
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($item in @($Body.output)) {
            foreach ($part in @($item.content)) { if ($part.text) { $parts.Add([string]$part.text) } }
        }
        $content = $parts -join ''
    }
    return $content
}

function New-RequestBody {
    param([ValidateSet('chat_completions', 'responses')][string]$Protocol, [string]$Model, [string]$Level, [bool]$Stream)
    if ($Protocol -eq 'responses') {
        $body = [ordered]@{
            model = $Model
            input = 'Reply with the single word READY.'
            max_output_tokens = 32
            stream = $Stream
        }
        if (-not [string]::IsNullOrWhiteSpace($Level)) { $body.reasoning = [ordered]@{ effort = $Level } }
        return $body
    }

    $body = [ordered]@{
        model = $Model
        messages = @([ordered]@{ role = 'user'; content = 'Reply with the single word READY.' })
        max_tokens = 32
        stream = $Stream
    }
    if (-not [string]::IsNullOrWhiteSpace($Level)) { $body.reasoning_effort = $Level }
    return $body
}

function Test-Protocol {
    param([string]$Protocol, [string]$Model)
    $response = Invoke-RelayJson -Uri (Join-RelayPath $(if ($Protocol -eq 'responses') { 'responses' } else { 'chat/completions' })) -Body (New-RequestBody -Protocol $Protocol -Model $Model -Level '' -Stream $false)
    $text = if ($Protocol -eq 'responses') { Get-ResponsesText $response.Body } else { Get-ChatText $response.Body }
    return [pscustomobject]@{
        protocol = $Protocol
        status = if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300 -and -not [string]::IsNullOrWhiteSpace($text)) { 'PASS' } else { 'FAIL' }
        http_status = $response.StatusCode
        text_received = -not [string]::IsNullOrWhiteSpace($text)
        detail = if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) { 'completion_received' } else { (Sanitize-Text ($response.Raw + ' ' + $response.Error)).Trim() }
    }
}

function Test-ReasoningLevel {
    param([string]$Protocol, [string]$Model, [string]$Level)
    $path = if ($Protocol -eq 'responses') { 'responses' } else { 'chat/completions' }
    $response = Invoke-RelayJson -Uri (Join-RelayPath $path) -Body (New-RequestBody -Protocol $Protocol -Model $Model -Level $Level -Stream $false)
    $text = if ($Protocol -eq 'responses') { Get-ResponsesText $response.Body } else { Get-ChatText $response.Body }
    $detail = (Sanitize-Text ($response.Raw + ' ' + $response.Error)).Trim()
    $unsupported = $response.StatusCode -in @(400, 404, 422) -and $detail -match '(?i)reasoning|unsupported|not supported|invalid'
    $status = if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300 -and -not [string]::IsNullOrWhiteSpace($text)) { 'PASS' } elseif ($unsupported) { 'UNSUPPORTED' } else { 'FAIL' }
    return [pscustomobject]@{
        value = $Level
        status = $status
        http_status = $response.StatusCode
        text_received = -not [string]::IsNullOrWhiteSpace($text)
        detail = if ($status -eq 'PASS') { 'reasoning_parameter_accepted' } elseif ($status -eq 'UNSUPPORTED') { 'relay_does_not_accept_this_reasoning_level' } else { $detail }
    }
}

function Test-Streaming {
    param([string]$Protocol, [string]$Model, [string]$Level)
    $path = if ($Protocol -eq 'responses') { 'responses' } else { 'chat/completions' }
    $uri = Join-RelayPath $path
    $body = New-RequestBody -Protocol $Protocol -Model $Model -Level $Level -Stream $true
    $bodyJson = $body | ConvertTo-Json -Depth 20 -Compress
    $http = [System.Net.Http.HttpClient]::new()
    try {
        for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
            $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $uri)
            $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $apiKey)
            $request.Headers.Accept.ParseAdd('text/event-stream')
            $request.Content = [System.Net.Http.StringContent]::new($bodyJson, [Text.Encoding]::UTF8, 'application/json')
            try {
                $response = $http.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                $raw = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                $hasData = $raw -match '(?m)^data:\s*.+$'
                $status = [int]$response.StatusCode
                if ($response.IsSuccessStatusCode -and $hasData) {
                    return [pscustomobject]@{ status = 'PASS'; http_status = $status; detail = 'sse_data_received' }
                }
                if ($status -notin @(429, 502, 503, 504) -or $attempt -ge $RetryCount) {
                    return [pscustomobject]@{ status = 'FAIL'; http_status = $status; detail = (Sanitize-Text $raw) }
                }
            } catch {
                if ($attempt -ge $RetryCount) {
                    return [pscustomobject]@{ status = 'FAIL'; http_status = 0; detail = (Sanitize-Text $_.Exception.Message) }
                }
            } finally {
                $request.Dispose()
            }
            if ($RetryDelaySec -gt 0) { Start-Sleep -Seconds $RetryDelaySec }
        }
    } finally {
        $http.Dispose()
    }
}

$approvedTextModels = @('gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5')
$levels = @('low', 'medium', 'high')
$values = Read-DotEnv -Path $EnvPath
$baseUrl = Get-Value -Values $values -Name 'AGENTOS_LLM_BASE_URL'
$apiKey = Get-Value -Values $values -Name 'AGENTOS_LLM_API_KEY'
$preferredProtocol = (Get-Value -Values $values -Name 'AGENTOS_LLM_PROTOCOL' -Default 'chat_completions').ToLowerInvariant()
$protocolResults = [System.Collections.Generic.List[object]]::new()
$modelResults = [System.Collections.Generic.List[object]]::new()
$selectedProtocol = $null

if ($preferredProtocol -notin @('chat_completions', 'responses')) {
    $protocolResults.Add([pscustomobject]@{ protocol = $preferredProtocol; status = 'FAIL'; http_status = 0; text_received = $false; detail = 'unsupported_protocol_setting' })
} elseif (-not (Test-Present $baseUrl) -or -not (Test-Present $apiKey)) {
    $protocolResults.Add([pscustomobject]@{ protocol = $preferredProtocol; status = 'BLOCKED'; http_status = 0; text_received = $false; detail = 'relay_configuration_missing' })
} else {
    foreach ($protocol in @('chat_completions', 'responses')) {
        $probe = Test-Protocol -Protocol $protocol -Model 'gpt-5.5'
        $protocolResults.Add($probe)
    }
    $preferredResult = @($protocolResults | Where-Object { $_.protocol -eq $preferredProtocol -and $_.status -eq 'PASS' }) | Select-Object -First 1
    $fallbackResult = @($protocolResults | Where-Object { $_.status -eq 'PASS' }) | Select-Object -First 1
    if ($null -ne $preferredResult) { $selectedProtocol = $preferredResult.protocol } elseif ($null -ne $fallbackResult) { $selectedProtocol = $fallbackResult.protocol }
}

foreach ($modelName in $approvedTextModels) {
    $levelResults = [System.Collections.Generic.List[object]]::new()
    foreach ($level in $levels) {
        if ($null -eq $selectedProtocol) {
            $levelResults.Add([pscustomobject]@{ value = $level; status = 'BLOCKED'; http_status = 0; text_received = $false; detail = 'no_working_text_protocol' })
        } else {
            $levelResults.Add((Test-ReasoningLevel -Protocol $selectedProtocol -Model $modelName -Level $level))
        }
    }
    $modelResults.Add([pscustomobject]@{
        model = $modelName
        levels = @($levelResults)
        supported_levels = @($levelResults | Where-Object status -eq 'PASS' | ForEach-Object value)
    })
}

$streaming = if ($null -eq $selectedProtocol) {
    [pscustomobject]@{ status = 'BLOCKED'; http_status = 0; detail = 'no_working_text_protocol' }
} else {
    $streamLevel = @($modelResults[0].levels | Where-Object status -eq 'PASS' | Select-Object -First 1 | ForEach-Object value)
    Test-Streaming -Protocol $selectedProtocol -Model 'gpt-5.5' -Level ([string]$streamLevel)
}

$unexpectedFailures = @($modelResults.levels | Where-Object status -eq 'FAIL').Count -gt 0
$modelsWithCapability = @($modelResults | Where-Object { @($_.supported_levels).Count -gt 0 }).Count -eq $approvedTextModels.Count
$preferredProtocolResult = @($protocolResults | Where-Object { $_.protocol -eq $preferredProtocol } | Select-Object -First 1)
$preferredProtocolReady = $null -ne $preferredProtocolResult -and $preferredProtocolResult.status -eq 'PASS'
$gate = if ($null -eq $selectedProtocol -or -not $preferredProtocolReady -or $unexpectedFailures -or -not $modelsWithCapability -or $streaming.status -ne 'PASS') { 'FAIL' } else { 'PASS' }
if (-not (Test-Present $baseUrl) -or -not (Test-Present $apiKey)) { $gate = 'BLOCKED' }

$report = [ordered]@{
    schema_version = 'agentos.v0.3.1.reasoning-matrix.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    preferred_protocol = $preferredProtocol
    protocol = $selectedProtocol
    preferred_protocol_status = if ($null -ne $preferredProtocolResult) { $preferredProtocolResult.status } else { 'MISSING' }
    retry_policy = [ordered]@{ retry_statuses = @(429, 502, 503, 504); max_attempts = $RetryCount; delay_seconds = $RetryDelaySec }
    reasoning_parameter = if ($selectedProtocol -eq 'responses') { 'reasoning.effort' } else { 'reasoning_effort' }
    protocols = @($protocolResults)
    streaming = $streaming
    models = @($modelResults)
    gate = $gate
}

foreach ($path in @($ReportPath, $MatrixPath)) {
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
}

Write-Host "V0.3.1 reasoning probe: $gate. Protocol=$selectedProtocol. Report=$ReportPath"
if ($gate -eq 'FAIL') { exit 1 }
if ($gate -eq 'BLOCKED') { exit 2 }
exit 0
