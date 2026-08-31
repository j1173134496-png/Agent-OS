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
& docker compose @composeArgs ps
exit $LASTEXITCODE

