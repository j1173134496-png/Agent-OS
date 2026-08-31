[CmdletBinding()]
param(
    [string]$Service,
    [int]$Tail = 200
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envPath = Join-Path $root '.env'
$composePath = Join-Path $root 'deployment\compose.yaml'

if (-not (Test-Path $envPath)) {
    throw "Missing $envPath. Run .\scripts\New-AgentOSEnv.ps1 first."
}

$composeArgs = @('--project-name', 'agentos', '--env-file', $envPath, '-f', $composePath, 'logs', '--tail', "$Tail")
if ($Service) { $composeArgs += $Service }
& docker compose @composeArgs
exit $LASTEXITCODE

