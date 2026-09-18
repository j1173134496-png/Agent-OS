[CmdletBinding()]
param(
    [string]$MongoContainer = 'agentos-mongodb',
    [string]$Database = 'LibreChat',
    [string]$BaseUrl = 'http://localhost:3080',
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.2\V0.3.2_GATE_REPORT.json'
}

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param([string]$Id, [bool]$Passed, [string]$Details)
    $checks.Add([ordered]@{
        id = $Id
        status = if ($Passed) { 'PASS' } else { 'FAIL' }
        details = $Details
    })
}

function Invoke-MongoJson {
    param([Parameter(Mandatory = $true)][string]$Expression)
    $eval = "print(EJSON.stringify($Expression))"
    $raw = @(& docker exec $MongoContainer mongosh --quiet $Database --eval $eval 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "MongoDB gate query failed: $($raw -join ' ')"
    }
    $line = @($raw | ForEach-Object { [string]$_ } | Where-Object {
        $_.Trim().StartsWith('{') -or $_.Trim().StartsWith('[')
    } | Select-Object -Last 1)
    if ($line.Count -eq 0) {
        throw "MongoDB gate query returned no JSON: $($raw -join ' ')"
    }
    return $line[0] | ConvertFrom-Json
}

$staticReportPath = Join-Path $root 'deployment\runtime\v0.3.2\static-report.json'
$staticExit = 0
try {
    & (Join-Path $PSScriptRoot 'Test-AgentOSV032Static.ps1') -ReportPath $staticReportPath | Out-Null
    $staticExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
} catch {
    $staticExit = 1
}
Add-Check 'static-gate' ($staticExit -eq 0) 'Static V0.3.2 contract and legacy-freeze checks.'

$policyReportPath = Join-Path $root 'deployment\runtime\v0.3.2\policy-sync-report.json'
Add-Check 'policy-report' (Test-Path -LiteralPath $policyReportPath -PathType Leaf) 'Role-policy synchronization report exists.'

$roles = $null
$agent = $null
$collections = $null
$manifest = Get-Content -LiteralPath (Join-Path $root 'deployment\agents\smart-submit-v1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
try {
    $roles = Invoke-MongoJson "db.roles.find({name: {`$in: ['ADMIN','USER']}}, {name: 1, permissions: 1, _id: 0}).toArray()"
    $agentId = [string]$manifest.agent_id
    $agent = Invoke-MongoJson "db.agents.findOne({id: '$agentId'}, {_id: 0, id: 1, name: 1, business_agent_id: 1, publication_status: 1, business_version: 1, allowed_roles: 1, skills: 1, skills_enabled: 1, tools: 1, mcpServerNames: 1, release_metadata: 1})"
    $collections = Invoke-MongoJson 'db.getCollectionNames()'
} catch {
    Add-Check 'mongodb-contract-query' $false $_.Exception.Message
}

$roleMap = @{}
foreach ($role in @($roles)) {
    $roleMap[[string]$role.name] = $role
}
$adminPolicy = $false
$userPolicy = $false
if ($roleMap.ContainsKey('ADMIN') -and $roleMap.ContainsKey('USER')) {
    $adminPermissions = $roleMap.ADMIN.permissions
    $userPermissions = $roleMap.USER.permissions
    $adminPolicy = $adminPermissions.AGENTS.USE -eq $true -and
        $adminPermissions.AGENTS.CREATE -eq $true -and
        $adminPermissions.AGENTS.SHARE -eq $false -and
        $adminPermissions.SKILLS.USE -eq $true -and
        $adminPermissions.SKILLS.CREATE -eq $true -and
        $adminPermissions.MARKETPLACE.USE -eq $true
    $userPolicy = $userPermissions.AGENTS.USE -eq $true -and
        $userPermissions.AGENTS.CREATE -eq $false -and
        $userPermissions.AGENTS.SHARE -eq $false -and
        $userPermissions.AGENTS.SHARE_PUBLIC -eq $false -and
        $userPermissions.SKILLS.USE -eq $true -and
        $userPermissions.SKILLS.CREATE -eq $false -and
        $userPermissions.SKILLS.SHARE -eq $false -and
        $userPermissions.MARKETPLACE.USE -eq $true
}
Add-Check 'admin-policy' $adminPolicy 'ADMIN can create/publish managed Agents and Skills, while ad-hoc sharing stays disabled.'
Add-Check 'employee-policy' $userPolicy 'USER can use Marketplace and native company resources but cannot create/edit/share them.'

$agentPolicy = $null -ne $agent -and
    $agent.publication_status -eq 'published' -and
    $agent.business_version -eq '1.0.0' -and
    $agent.skills_enabled -eq $true -and
    @($agent.allowed_roles) -contains 'USER' -and
    @($agent.allowed_roles) -contains 'ADMIN' -and
    @($agent.skills).Count -eq 1 -and
    @($agent.tools).Count -eq 7 -and
    @($agent.mcpServerNames) -contains 'submit-flow' -and
    $agent.release_metadata.release_id -eq 'agentos-v0.3.2-smart-submit-v1'
Add-Check 'published-agent' $agentPolicy 'Managed Smart Submit Agent is published with locked native Skill/MCP/tool references and release metadata.'

$legacyCollectionPresent = @($collections) -contains 'agentos_conversation_plugins'
Add-Check 'legacy-state-freeze' $legacyCollectionPresent 'Legacy conversation plugin state remains present for one rollback/audit cycle.'

$marketplaceStatus = $null
try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/api/agents/marketplace?requiredPermission=1&limit=1" -TimeoutSec 10
    $marketplaceStatus = [int]$response.StatusCode
} catch {
    if ($null -ne $_.Exception.Response) {
        $marketplaceStatus = [int]$_.Exception.Response.StatusCode
    }
}
Add-Check 'marketplace-auth-boundary' ($marketplaceStatus -in @(401, 403)) "Unauthenticated Marketplace access is rejected by the server (HTTP $marketplaceStatus)."

$readyStatus = $null
$readyBody = $null
try {
    $readyResponse = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/readyz" -TimeoutSec 10
    $readyStatus = [int]$readyResponse.StatusCode
    $readyBody = $readyResponse.Content.Trim()
} catch {
    if ($null -ne $_.Exception.Response) {
        $readyStatus = [int]$_.Exception.Response.StatusCode
    }
}
Add-Check 'runtime-ready' ($readyStatus -eq 200 -and $readyBody -eq 'OK') "Runtime readiness is HTTP $readyStatus with body '$readyBody'."

$report = [ordered]@{
    schema_version = 'agentos.v0.3.2.gate-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    release = 'V0.3.2'
    checks = @($checks)
    gate = if (@($checks | Where-Object status -eq 'FAIL').Count -eq 0) { 'PASS' } else { 'FAIL' }
}
$reportDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReportPath -Encoding UTF8

if ($report.gate -ne 'PASS') {
    Write-Host "V0.3.2 runtime gate FAILED: $ReportPath"
    exit 1
}
Write-Host "V0.3.2 runtime gate PASSED: $ReportPath"
