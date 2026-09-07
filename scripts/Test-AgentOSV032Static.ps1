[CmdletBinding()]
param(
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.2\static-report.json'
}

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param(
        [string]$Id,
        [bool]$Passed,
        [string]$Details
    )
    $checks.Add([ordered]@{
        id = $Id
        status = if ($Passed) { 'PASS' } else { 'FAIL' }
        details = $Details
    })
}
function Read-RequiredFile {
    param([string]$RelativePath)
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required V0.3.2 file is missing: $RelativePath"
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8
}

$manifestText = Read-RequiredFile 'deployment\agents\smart-submit-v1.json'
$registryText = Read-RequiredFile 'deployment\agents\native-tool-registry.json'
$configText = Read-RequiredFile 'deployment\librechat.yaml'
$routeText = Read-RequiredFile 'source\librechat-maintained\api\server\routes\agents\v1.js'
$controllerText = Read-RequiredFile 'source\librechat-maintained\api\server\controllers\agents\v1.js'
$favoritesText = Read-RequiredFile 'source\librechat-maintained\api\server\controllers\FavoritesController.js'
$serviceText = Read-RequiredFile 'source\librechat-maintained\packages\data-provider\src\data-service.ts'
$toolsMenuText = Read-RequiredFile 'source\librechat-maintained\client\src\components\Chat\Input\ToolsDropdown.tsx'
$themeText = Read-RequiredFile 'source\librechat-maintained\client\src\agentos-theme.css'
$rolesText = Read-RequiredFile 'source\librechat-maintained\packages\data-provider\src\roles.ts'
$migrationText = Read-RequiredFile 'deployment\runtime\v0.3.2\legacy-plugin-migration.json'
$newConvoText = Read-RequiredFile 'source\librechat-maintained\client\src\hooks\useNewConvo.ts'

$manifest = $manifestText | ConvertFrom-Json
$registry = $registryText | ConvertFrom-Json

Add-Check 'AOS-032-01-release-manifest' (
    $manifest.schema_version -eq 'agentos.agent-release.v1' -and
    $manifest.publication_status -eq 'published' -and
    -not [string]::IsNullOrWhiteSpace([string]$manifest.business_version) -and
    $null -ne $manifest.release_record
) 'Versioned Agent release manifest has publication status, business version, and release record.'

Add-Check 'AOS-032-01-native-registry' (
    $registry.schema_version -eq 'agentos.native-tool-registry.v1' -and
    @($registry.native_tools).Count -eq @($registry.contract_tools).Count -and
    @($registry.mcp_servers.PSObject.Properties).Count -gt 0
) 'Native MCP tool registry contains one-to-one contract/native references and MCP registration.'

Add-Check 'AOS-032-02-marketplace-boundary' (
    $routeText -match "GET /agents/marketplace" -and
    $routeText -match "PermissionTypes\.MARKETPLACE" -and
    $routeText -match "'/marketplace'" -and
    $controllerText -match "publication_status = 'published'" -and
    $controllerText -match 'allowed_roles'
) 'Marketplace has a dedicated route, Marketplace USE permission, and published/role filtering.'

Add-Check 'AOS-032-02-agent-start-routing' (
    $newConvoText -match 'isAgentTemplate' -and
    $newConvoText -match '\{ \.\.\._template, agent_id: agentId \}' -and
    $newConvoText -match 'conversation\.agent_id = activePreset\.agent_id' -and
    $newConvoText -match 'routeAgentId' -and
    $newConvoText -match 'nextParams\.set\(''agent_id'', routeAgentId\)' -and
    $newConvoText -match 'nextParams\.delete\(''spec''\)' -and
    (Read-RequiredFile 'source\librechat-maintained\client\src\hooks\Input\useQueryParams.ts') -match "preservedParams\.set\('agent_id', agentId\)"
) 'Starting a Marketplace Agent preserves native agent_id routing instead of falling back to the default text model spec.'

$agentDetailText = Read-RequiredFile 'source\librechat-maintained\client\src\components\Agents\AgentDetail.tsx'
$agentDetailContentText = Read-RequiredFile 'source\librechat-maintained\client\src\components\Agents\AgentDetailContent.tsx'
Add-Check 'AOS-032-02-marketplace-start-link' (
    $agentDetailText -match 'navigate\(`/c/\$\{Constants\.NEW_CONVO\}\?agent_id=' -and
    $agentDetailContentText -match 'navigate\(`/c/\$\{Constants\.NEW_CONVO\}\?agent_id='
) 'Both native Marketplace detail entry points navigate with an explicit Agent deep-link.'

Add-Check 'AOS-032-03-employee-permission-contract' (
    $rolesText -match '\[PermissionTypes\.AGENTS\]: \{' -and
    $rolesText -match '\[PermissionTypes\.SKILLS\]: \{' -and
    $rolesText -match '\[Permissions\.CREATE\]: false' -and
    $rolesText -match '\[PermissionTypes\.MARKETPLACE\]'
) 'USER defaults keep company Agent/Skill creation and sharing disabled while Marketplace remains explicit.'

Add-Check 'AOS-032-04-native-skills-agent-allowlist' (
    $controllerText -match 'skills_enabled' -and
    $controllerText -match 'configuredSkills' -and
    $manifestText -match 'skill_ids' -and
    $configText -match '(?m)^\s*skills:\s*$'
) 'Native Skill catalog, Agent Skill allowlist, and deployment Skill binding are present.'

Add-Check 'AOS-032-05-native-image-menu' (
    $toolsMenuText -match 'data-testid="tools-menu-image-generation"' -and
    $toolsMenuText -match 'handleImageGenerationToggle' -and
    $configText -match 'image_gen_oai'
) 'Image generation is exposed through LibreChat native Tools menu and native request state.'

Add-Check 'AOS-032-06-server-favorite-authorization' (
    $favoritesText -match 'findAccessibleResources' -and
    $favoritesText -match 'AGENT_VIEW_REQUIRED' -and
    $favoritesText -match 'resourceType: ResourceType\.AGENT'
) 'Favorites re-check Agent VIEW permission on the server before persisting.'

Add-Check 'AOS-032-07-generated-image-branding-regression' (
    $themeText -match "img\[src\*='/assets/image_gen_oai\." -and
    $themeText -notmatch "img\[src\*='/images/" -and
    $themeText -notmatch 'image_gen_oai[^\r\n]*generated'
) 'Brand CSS only targets known assets and does not target generated image paths.'

$activeLegacyFiles = @(
    'deployment\branding\agentos-plugins.js',
    'deployment\agentos-runtime',
    'deployment\plugins',
    'deployment\agentos-entrypoint.sh'
)
$legacyPresent = @($activeLegacyFiles | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) }).Count -gt 0
Add-Check 'AOS-032-08-legacy-plugin-freeze' (-not $legacyPresent -and $configText -notmatch 'agentos_plugin_ids' -and $migrationText -match 'FROZEN_FOR_ROLLBACK_AND_AUDIT') 'Legacy plugin runtime paths are absent from active deployment; rollback state is explicitly frozen and audited.'

$validatePassed = $true
$validateOutput = @()
try {
    $validateOutput = @(& (Join-Path $PSScriptRoot 'Sync-AgentOSAgents.ps1') -ValidateOnly -Quiet 2>&1)
} catch {
    $validatePassed = $false
    $validateOutput = @($_.Exception.Message)
}
Add-Check 'AOS-032-09-release-reference-validation' $validatePassed 'Release manifest Skill, Tool, MCP, model, role, and acceptance references validate.'

$report = [ordered]@{
    schema_version = 'agentos.v0.3.2.static-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    checks = @($checks)
    gate = if (@($checks | Where-Object status -eq 'FAIL').Count -eq 0) { 'PASS' } else { 'FAIL' }
    validator_output = @($validateOutput | ForEach-Object { [string]$_ })
}
$reportDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($report.gate -ne 'PASS') {
    Write-Host "V0.3.2 static gate FAILED: $ReportPath"
    exit 1
}
Write-Host "V0.3.2 static gate PASSED: $ReportPath"
