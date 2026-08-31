[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath,
    [int]$TimeoutSec = 45
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $root 'deployment\runtime\v0.2\capability-report.json' }

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

if (-not (Test-Path -LiteralPath $EnvPath)) {
    throw "Missing private environment file: $EnvPath"
}

$envValues = Read-DotEnv -Path $EnvPath
$baseUrl = Get-Value -Values $envValues -Name 'AGENTOS_LLM_BASE_URL'
$apiKey = Get-Value -Values $envValues -Name 'AGENTOS_LLM_API_KEY'
$model = Get-Value -Values $envValues -Name 'AGENTOS_LLM_MODEL'
$protocol = (Get-Value -Values $envValues -Name 'AGENTOS_LLM_PROTOCOL' -Default 'chat_completions').ToLowerInvariant()

function Get-SafeUri {
    param([string]$Value)
    try {
        $uri = [System.Uri]$Value
        if (-not $uri.IsAbsoluteUri) { return '[invalid-url]' }
        $port = if ($uri.IsDefaultPort) { '' } else { ":$($uri.Port)" }
        $path = $uri.AbsolutePath.TrimEnd('/')
        return "$($uri.Scheme)://$($uri.Host)$port$path"
    } catch {
        return '[invalid-url]'
    }
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
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [AllowNull()][object]$Body
    )

    $headers = @{
        Authorization = "Bearer $apiKey"
        Accept = 'application/json'
    }
    $jsonBody = $null
    if ($null -ne $Body) {
        $jsonBody = $Body | ConvertTo-Json -Depth 30 -Compress
    }

    try {
        $requestParams = @{
            Method = $Method
            Uri = $Uri
            Headers = $headers
            UseBasicParsing = $true
            TimeoutSec = $TimeoutSec
        }
        if ($null -ne $jsonBody) {
            $requestParams.ContentType = 'application/json'
            $requestParams.Body = $jsonBody
        }
        $response = Invoke-WebRequest @requestParams
        $parsed = $response.Content | ConvertFrom-Json
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $parsed; Raw = [string]$response.Content }
    } catch {
        $detail = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
        throw (Sanitize-Text $detail)
    }
}

function Get-ChatText {
    param([object]$Body)
    $choices = @($Body.choices)
    if ($choices.Count -eq 0 -or $null -eq $choices[0].message) { throw 'Response has no chat completion choice.' }
    $content = [string]$choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) { throw 'Chat completion returned empty content.' }
    return $content
}

function Get-ResponsesText {
    param([object]$Body)
    $content = [string]$Body.output_text
    if ([string]::IsNullOrWhiteSpace($content) -and $Body.output) {
        $parts = @()
        foreach ($item in @($Body.output)) {
            foreach ($part in @($item.content)) {
                if ($part.text) { $parts += [string]$part.text }
            }
        }
        $content = $parts -join ''
    }
    if ([string]::IsNullOrWhiteSpace($content)) { throw 'Responses API returned empty output text.' }
    return $content
}

function Get-ResponsesStreamText {
    param([string]$Raw)
    $matches = [regex]::Matches($Raw, '(?m)^data:\s*(.+)$')
    if ($matches.Count -eq 0) { throw 'The Responses stream returned no SSE data lines.' }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($match in $matches) {
        $line = $match.Groups[1].Value.Trim()
        if ($line -eq '[DONE]') { continue }
        try {
            $event = $line | ConvertFrom-Json
            if ($event.delta) { $parts.Add([string]$event.delta) }
        } catch {
            # Providers may emit non-JSON or non-text events.
        }
    }
    $content = $parts -join ''
    if ([string]::IsNullOrWhiteSpace($content)) { throw 'The Responses stream contained no text delta.' }
    return $content
}

function New-ToolParameters {
    return [ordered]@{
        type = 'object'
        properties = [ordered]@{
            city = [ordered]@{ type = 'string'; description = 'A city name.' }
        }
        required = @('city')
        additionalProperties = $false
    }
}

function New-JsonSchema {
    return [ordered]@{
        type = 'object'
        properties = [ordered]@{
            ok = [ordered]@{ type = 'boolean' }
            round = [ordered]@{ type = 'integer' }
        }
        required = @('ok', 'round')
        additionalProperties = $false
    }
}

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail, [int]$LatencyMs = 0)
    $results.Add([ordered]@{
        name = $Name
        status = $Status
        latency_ms = $LatencyMs
        detail = (Sanitize-Text $Detail)
    })
}

function Invoke-Probe {
    param([string]$Name, [scriptblock]$Action)
    $started = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $detail = & $Action
        $started.Stop()
        Add-Result -Name $Name -Status 'PASS' -Detail ([string]$detail) -LatencyMs ([int]$started.ElapsedMilliseconds)
    } catch {
        $started.Stop()
        Add-Result -Name $Name -Status 'FAIL' -Detail ([string]$_.Exception.Message) -LatencyMs ([int]$started.ElapsedMilliseconds)
    }
}

function Test-ChatCompletion {
    $body = [ordered]@{
        model = $model
        messages = @([ordered]@{ role = 'user'; content = 'Reply with the single word READY.' })
        stream = $false
    }
    $response = Invoke-RelayJson -Method POST -Uri (Join-RelayPath 'chat/completions') -Body $body
    $content = Get-ChatText -Body $response.Body
    return "content_bytes=$([Text.Encoding]::UTF8.GetByteCount($content))"
}

function Test-ChatStream {
    $body = [ordered]@{
        model = $model
        messages = @([ordered]@{ role = 'user'; content = 'Reply with the single word STREAM.' })
        stream = $true
    }
    $headers = @{ Authorization = "Bearer $apiKey"; Accept = 'text/event-stream' }
    $jsonBody = $body | ConvertTo-Json -Depth 20 -Compress
    try {
        $response = Invoke-WebRequest -Method POST -Uri (Join-RelayPath 'chat/completions') -Headers $headers -ContentType 'application/json' -Body $jsonBody -UseBasicParsing -TimeoutSec $TimeoutSec
    } catch {
        throw (Sanitize-Text $_.Exception.Message)
    }
    $matches = [regex]::Matches([string]$response.Content, '(?m)^data:\s*(.+)$')
    if ($matches.Count -eq 0) { throw 'The relay returned no SSE data lines.' }
    $contentBytes = 0
    foreach ($match in $matches) {
        $line = $match.Groups[1].Value.Trim()
        if ($line -eq '[DONE]') { continue }
        try {
            $event = $line | ConvertFrom-Json
            $delta = [string]$event.choices[0].delta.content
            if ($delta) { $contentBytes += [Text.Encoding]::UTF8.GetByteCount($delta) }
        } catch {
            # Ignore provider-specific SSE events that are not JSON chat chunks.
        }
    }
    if ($contentBytes -eq 0) { throw 'SSE connected but contained no text delta.' }
    return "sse_events=$($matches.Count);content_bytes=$contentBytes"
}

function Test-ChatTools {
    $function = [ordered]@{
        name = 'agentos_probe'
        description = 'Probe function used to verify tool calling.'
        parameters = New-ToolParameters
    }
    $body = [ordered]@{
        model = $model
        messages = @([ordered]@{ role = 'user'; content = 'Call agentos_probe exactly once with city=Shenzhen.' })
        tools = @([ordered]@{ type = 'function'; function = $function })
        tool_choice = [ordered]@{ type = 'function'; function = [ordered]@{ name = 'agentos_probe' } }
        stream = $false
    }
    $response = Invoke-RelayJson -Method POST -Uri (Join-RelayPath 'chat/completions') -Body $body
    $calls = @($response.Body.choices[0].message.tool_calls)
    if ($calls.Count -eq 0) { throw 'The model returned no tool_calls.' }
    $name = [string]$calls[0].function.name
    if ($name -ne 'agentos_probe') { throw "Unexpected tool name: $name" }
    return 'tool_call=agentos_probe'
}

function Test-ChatJsonSchema {
    $format = [ordered]@{
        type = 'json_schema'
        json_schema = [ordered]@{
            name = 'agentos_probe'
            strict = $true
            schema = New-JsonSchema
        }
    }
    $body = [ordered]@{
        model = $model
        messages = @([ordered]@{ role = 'user'; content = 'Return JSON with ok=true and round=2.' })
        response_format = $format
        stream = $false
    }
    $response = Invoke-RelayJson -Method POST -Uri (Join-RelayPath 'chat/completions') -Body $body
    $content = Get-ChatText -Body $response.Body
    try { $parsed = $content | ConvertFrom-Json } catch { throw 'Response content was not valid JSON.' }
    if ($parsed.ok -ne $true -or [int]$parsed.round -ne 2) { throw 'JSON Schema response did not match the requested payload.' }
    return 'json_schema_valid=true'
}

function Test-ChatStreamInterruption {
    $http = [System.Net.Http.HttpClient]::new()
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, (Join-RelayPath 'chat/completions'))
    $body = [ordered]@{
        model = $model
        messages = @([ordered]@{ role = 'user'; content = 'Generate a long response so the client can stop after the first chunk.' })
        stream = $true
    }
    $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $apiKey)
    $request.Headers.Accept.ParseAdd('text/event-stream')
    $request.Content = [System.Net.Http.StringContent]::new(($body | ConvertTo-Json -Depth 20 -Compress), [Text.Encoding]::UTF8, 'application/json')
    $cancel = [System.Threading.CancellationTokenSource]::new()
    $response = $null
    $stream = $null
    try {
        $response = $http.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cancel.Token).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw "Unexpected stream status $([int]$response.StatusCode)." }
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $buffer = New-Object byte[] 4096
        $read = $stream.ReadAsync($buffer, 0, $buffer.Length).GetAwaiter().GetResult()
        if ($read -le 0) { throw 'The stream ended before the first chunk.' }
        $cancel.Cancel()
        return "client_cancelled_after_first_chunk=true;bytes=$read"
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        $cancel.Dispose()
        $request.Dispose()
        $http.Dispose()
    }
}

function Test-ResponsesCompletion {
    $body = [ordered]@{
        model = $model
        input = 'Reply with the single word READY.'
        stream = $false
    }
    $response = Invoke-RelayJson -Method POST -Uri (Join-RelayPath 'responses') -Body $body
    $content = Get-ResponsesText -Body $response.Body
    return "content_bytes=$([Text.Encoding]::UTF8.GetByteCount($content))"
}

function Test-ResponsesStream {
    $body = [ordered]@{
        model = $model
        input = 'Reply with the single word STREAM.'
        stream = $true
    }
    $headers = @{ Authorization = "Bearer $apiKey"; Accept = 'text/event-stream' }
    try {
        $response = Invoke-WebRequest -Method POST -Uri (Join-RelayPath 'responses') -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 20 -Compress) -UseBasicParsing -TimeoutSec $TimeoutSec
    } catch {
        throw (Sanitize-Text $_.Exception.Message)
    }
    $content = Get-ResponsesStreamText -Raw ([string]$response.Content)
    return "content_bytes=$([Text.Encoding]::UTF8.GetByteCount($content))"
}

function Test-ResponsesTools {
    $body = [ordered]@{
        model = $model
        input = 'Call agentos_probe exactly once with city=Shenzhen.'
        tools = @([ordered]@{
            type = 'function'
            name = 'agentos_probe'
            description = 'Probe function used to verify tool calling.'
            parameters = New-ToolParameters
            strict = $true
        })
        tool_choice = [ordered]@{ type = 'function'; name = 'agentos_probe' }
        stream = $false
    }
    $response = Invoke-RelayJson -Method POST -Uri (Join-RelayPath 'responses') -Body $body
    $calls = @($response.Body.output | Where-Object { $_.type -eq 'function_call' })
    if ($calls.Count -eq 0) { throw 'The Responses API returned no function_call output item.' }
    if ([string]$calls[0].name -ne 'agentos_probe') { throw "Unexpected function name: $($calls[0].name)" }
    return 'tool_call=agentos_probe'
}

function Test-ResponsesJsonSchema {
    $body = [ordered]@{
        model = $model
        input = 'Return JSON with ok=true and round=2.'
        text = [ordered]@{
            format = [ordered]@{
                type = 'json_schema'
                name = 'agentos_probe'
                strict = $true
                schema = New-JsonSchema
            }
        }
        stream = $false
    }
    $response = Invoke-RelayJson -Method POST -Uri (Join-RelayPath 'responses') -Body $body
    $content = Get-ResponsesText -Body $response.Body
    try { $parsed = $content | ConvertFrom-Json } catch { throw 'Responses content was not valid JSON.' }
    if ($parsed.ok -ne $true -or [int]$parsed.round -ne 2) { throw 'Responses JSON Schema output did not match the requested payload.' }
    return 'json_schema_valid=true'
}

function Test-ResponsesStreamInterruption {
    $http = [System.Net.Http.HttpClient]::new()
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, (Join-RelayPath 'responses'))
    $body = [ordered]@{
        model = $model
        input = 'Generate a long response so the client can stop after the first chunk.'
        stream = $true
    }
    $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $apiKey)
    $request.Headers.Accept.ParseAdd('text/event-stream')
    $request.Content = [System.Net.Http.StringContent]::new(($body | ConvertTo-Json -Depth 20 -Compress), [Text.Encoding]::UTF8, 'application/json')
    $cancel = [System.Threading.CancellationTokenSource]::new()
    $response = $null
    $stream = $null
    try {
        $response = $http.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cancel.Token).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw "Unexpected Responses stream status $([int]$response.StatusCode)." }
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $buffer = New-Object byte[] 4096
        $read = $stream.ReadAsync($buffer, 0, $buffer.Length).GetAwaiter().GetResult()
        if ($read -le 0) { throw 'The Responses stream ended before the first chunk.' }
        $cancel.Cancel()
        return "client_cancelled_after_first_chunk=true;bytes=$read"
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        $cancel.Dispose()
        $request.Dispose()
        $http.Dispose()
    }
}

$report = [ordered]@{
    schema_version = 'agentos.v0.2.capability-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    protocol = $protocol
    relay_base_url = (Get-SafeUri $baseUrl)
    model_configured = (Test-Present $model)
    tests = $results
    gate = 'BLOCKED'
}

$complete = (Test-Present $baseUrl) -and (Test-Present $apiKey) -and (Test-Present $model)
if ($protocol -notin @('chat_completions', 'responses')) {
    Add-Result -Name 'relay_protocol' -Status 'FAIL' -Detail "Unsupported protocol: $protocol"
} elseif (-not $complete) {
    Add-Result -Name 'relay_configuration' -Status 'BLOCKED' -Detail 'Set AGENTOS_LLM_BASE_URL, AGENTOS_LLM_API_KEY, and AGENTOS_LLM_MODEL in the private .env.'
} elseif ($protocol -eq 'responses') {
    Invoke-Probe -Name 'responses' -Action { Test-ResponsesCompletion }
    Invoke-Probe -Name 'streaming' -Action { Test-ResponsesStream }
    Invoke-Probe -Name 'tool_calling' -Action { Test-ResponsesTools }
    Invoke-Probe -Name 'json_schema' -Action { Test-ResponsesJsonSchema }
    Invoke-Probe -Name 'stream_interruption' -Action { Test-ResponsesStreamInterruption }
} else {
    Invoke-Probe -Name 'chat_completions' -Action { Test-ChatCompletion }
    Invoke-Probe -Name 'streaming' -Action { Test-ChatStream }
    Invoke-Probe -Name 'tool_calling' -Action { Test-ChatTools }
    Invoke-Probe -Name 'json_schema' -Action { Test-ChatJsonSchema }
    Invoke-Probe -Name 'stream_interruption' -Action { Test-ChatStreamInterruption }
}

$report.tests = $results
$hasFailure = @($results | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$hasBlocked = @($results | Where-Object { $_.status -eq 'BLOCKED' }).Count -gt 0
if ($hasFailure) { $report.gate = 'FAIL' }
elseif ($hasBlocked) { $report.gate = 'BLOCKED' }
else { $report.gate = 'PASS' }

$reportParent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $reportParent)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

Write-Host "V0.2 relay capability gate: $($report.gate). Report: $ReportPath"
if ($report.gate -eq 'FAIL') { exit 1 }
if ($report.gate -eq 'BLOCKED') { exit 2 }
exit 0
