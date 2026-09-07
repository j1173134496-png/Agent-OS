[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envPath = Join-Path $root '.env'
$composePath = Join-Path $root 'deployment\compose.yaml'

if (-not (Test-Path $envPath)) {
    throw "Missing $envPath. Run .\scripts\New-AgentOSEnv.ps1 first."
}

& (Join-Path $PSScriptRoot 'Sync-AgentOSV031Config.ps1')

$composeArgs = @('--project-name', 'agentos', '--env-file', $envPath, '-f', $composePath)
& docker compose @composeArgs up -d --force-recreate
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& (Join-Path $PSScriptRoot 'Sync-AgentOSAgents.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'AgentOS V0.3.1 services are starting. Run .\scripts\Health-AgentOS.ps1 when ready.'
