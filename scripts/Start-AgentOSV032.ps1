[CmdletBinding()]
param(
    # A fresh database has no ADMIN account yet. BootstrapOnly starts the Web
    # and database so the operator can register the first administrator before
    # applying declarative role and Agent configuration.
    [switch]$BootstrapOnly
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envPath = Join-Path $root '.env'
$composePath = Join-Path $root 'deployment\compose.yaml'

if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Missing $envPath. Run .\scripts\New-AgentOSEnv.ps1 first."
}

& (Join-Path $PSScriptRoot 'Sync-AgentOSV031Config.ps1')
if (-not $?) { exit 1 }

$composeArgs = @('--project-name', 'agentos', '--env-file', $envPath, '-f', $composePath)
& docker compose @composeArgs up -d --force-recreate
if (-not $?) { exit 1 }

if ($BootstrapOnly) {
    Write-Host 'AgentOS bootstrap services are starting.'
    Write-Host 'Register the first administrator at http://localhost:3080, then run scripts/macos/apply-system-config.sh (macOS) or this script again without -BootstrapOnly (Windows).'
    return
}

& (Join-Path $PSScriptRoot 'Sync-AgentOSV032Policy.ps1')
if (-not $?) { exit 1 }

& (Join-Path $PSScriptRoot 'Sync-AgentOSAgents.ps1')
if (-not $?) { exit 1 }

Write-Host 'AgentOS V0.3.2 services are starting. Run .\scripts\Health-AgentOS.ps1 and .\scripts\Test-AgentOSV032Gate.ps1 when ready.'
