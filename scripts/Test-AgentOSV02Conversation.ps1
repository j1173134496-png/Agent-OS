[CmdletBinding()]
param(
    [string]$EnvPath,
    [string]$ReportPath,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $root '.env' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $root 'deployment\runtime\v0.2\conversation-regression.json' }

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
    if ($text.Length -gt 500) { $text = $text.Substring(0, 500) }
    return $text
}

function Join-RelayPath {
    param([string]$Path)
    $apiBaseUrl = $baseUrl.TrimEnd('/')
    if ($apiBaseUrl -notmatch '/v1$') { $apiBaseUrl += '/v1' }
    return "$apiBaseUrl/$($Path.TrimStart('/'))"
}

function Get-SSEText {
    param([string]$Raw)
    $matches = [regex]::Matches($Raw, '(?m)^data:\s*(.+)$')
    if ($matches.Count -eq 0) { throw 'The relay returned no SSE data lines.' }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($match in $matches) {
        $line = $match.Groups[1].Value.Trim()
        if ($line -eq '[DONE]') { continue }
        try {
            $event = $line | ConvertFrom-Json
            $delta = [string]$event.choices[0].delta.content
            if ($delta) { $parts.Add($delta) }
        } catch {
            # Providers may emit non-chat SSE events; only text deltas matter here.
        }
    }
    $text = $parts -join ''
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'The stream contained no text delta.' }
    return $text
}

function Get-ResponsesSSEText {
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
    $text = $parts -join ''
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'The Responses stream contained no text delta.' }
    return $text
}

function Invoke-StreamingRound {
    param([array]$Messages)
    if ($protocol -eq 'responses') {
        $body = [ordered]@{ model = $model; input = $Messages; stream = $true }
        $uri = Join-RelayPath 'responses'
    } else {
        $body = [ordered]@{ model = $model; messages = $Messages; stream = $true }
        $uri = Join-RelayPath 'chat/completions'
    }
    $headers = @{ Authorization = "Bearer $apiKey"; Accept = 'text/event-stream' }
    try {
        return (Invoke-WebRequest -Method POST -Uri $uri -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 30 -Compress) -UseBasicParsing -TimeoutSec $TimeoutSec).Content
    } catch {
        throw (Sanitize-Text $_.Exception.Message)
    }
}

if (-not (Test-Path -LiteralPath $EnvPath)) { throw "Missing private environment file: $EnvPath" }
$envValues = Read-DotEnv -Path $EnvPath
$baseUrl = Get-Value -Values $envValues -Name 'AGENTOS_LLM_BASE_URL'
$apiKey = Get-Value -Values $envValues -Name 'AGENTOS_LLM_API_KEY'
$model = Get-Value -Values $envValues -Name 'AGENTOS_LLM_MODEL'
$protocol = (Get-Value -Values $envValues -Name 'AGENTOS_LLM_PROTOCOL' -Default 'chat_completions').ToLowerInvariant()

$rounds = [System.Collections.Generic.List[object]]::new()
$report = [ordered]@{
    schema_version = 'agentos.v0.2.conversation-regression.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    requested_rounds = 20
    completed_rounds = 0
    protocol = $protocol
    model_configured = (Test-Present $model)
    rounds = $rounds
    gate = 'BLOCKED'
}

$complete = (Test-Present $baseUrl) -and (Test-Present $apiKey) -and (Test-Present $model)
if ($protocol -notin @('chat_completions', 'responses')) {
    $rounds.Add([ordered]@{ round = 0; status = 'FAIL'; detail = "Unsupported protocol: $protocol" })
    $report.gate = 'FAIL'
} elseif (-not $complete) {
    $rounds.Add([ordered]@{ round = 0; status = 'BLOCKED'; detail = 'Set AGENTOS_LLM_BASE_URL, AGENTOS_LLM_API_KEY, and AGENTOS_LLM_MODEL in the private .env.' })
} else {
    $messages = [System.Collections.Generic.List[object]]::new()
    $failed = $false
    for ($round = 1; $round -le 20; $round++) {
        $messages.Add([ordered]@{
            role = 'user'
            content = "This is continuity regression round $round. Reply with exactly ROUND_${round}_OK and nothing else."
        })
        $started = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $raw = Invoke-StreamingRound -Messages @($messages)
            $text = if ($protocol -eq 'responses') { Get-ResponsesSSEText -Raw ([string]$raw) } else { Get-SSEText -Raw ([string]$raw) }
            if ($text -notmatch "ROUND_${round}_OK") { throw "Round $round response did not contain its continuity marker." }
            $started.Stop()
            $rounds.Add([ordered]@{ round = $round; status = 'PASS'; latency_ms = [int]$started.ElapsedMilliseconds; response_bytes = [Text.Encoding]::UTF8.GetByteCount($text) })
            $messages.Add([ordered]@{ role = 'assistant'; content = $text })
            $report.completed_rounds = $round
        } catch {
            $started.Stop()
            $rounds.Add([ordered]@{ round = $round; status = 'FAIL'; latency_ms = [int]$started.ElapsedMilliseconds; detail = (Sanitize-Text $_.Exception.Message) })
            $failed = $true
            break
        }
    }
    $report.gate = if ($failed) { 'FAIL' } else { 'PASS' }
}

if (@($rounds | Where-Object { $_.status -eq 'BLOCKED' }).Count -gt 0) { $report.gate = 'BLOCKED' }
$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

Write-Host "V0.2 conversation regression gate: $($report.gate) ($($report.completed_rounds)/20 rounds). Report: $ReportPath"
if ($report.gate -eq 'FAIL') { exit 1 }
if ($report.gate -eq 'BLOCKED') { exit 2 }
exit 0
