[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envPath = Join-Path $root '.env'
$composePath = Join-Path $root 'deployment\compose.yaml'

if (-not (Test-Path $envPath)) {
    throw "Missing $envPath. Run .\scripts\New-AgentOSEnv.ps1 first."
}

$composeArgs = @('--project-name', 'agentos', '--env-file', $envPath, '-f', $composePath)
$failed = $false

Write-Host 'Checking running containers...'
$services = @(& docker compose @composeArgs ps --services --filter status=running)
foreach ($required in @('api', 'mongodb')) {
    if ($services -notcontains $required) {
        Write-Error "Service is not running: $required"
        $failed = $true
    }
}

Write-Host 'Checking MongoDB...'
$mongoResult = & docker exec agentos-mongodb mongosh --quiet --eval "quit(db.adminCommand({ ping: 1 }).ok ? 0 : 1)" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error ($mongoResult -join [Environment]::NewLine)
    $failed = $true
} else {
    Write-Host 'MongoDB ping: OK'
}

Write-Host 'Checking Web endpoint...'
try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:3080/' -TimeoutSec 10
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
        throw "Unexpected HTTP status: $($response.StatusCode)"
    }
    Write-Host "Web endpoint: OK ($($response.StatusCode))"
} catch {
    Write-Error $_
    $failed = $true
}

Write-Host 'Checking readiness endpoint...'
try {
    $ready = Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:3080/readyz' -TimeoutSec 10
    if ($ready.StatusCode -ne 200 -or $ready.Content.Trim() -ne 'OK') {
        throw "Unexpected readiness response: $($ready.StatusCode)"
    }
    Write-Host 'Readiness endpoint: OK (200)'
} catch {
    Write-Error $_
    $failed = $true
}

if ($failed) {
    Write-Host 'V0.2 health check: FAIL'
    exit 1
}

Write-Host 'V0.2 health check: PASS'
