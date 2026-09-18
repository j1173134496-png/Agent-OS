[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ReleasePath,
    [string]$MongoContainer = 'agentos-mongodb',
    [string]$Database = 'LibreChat',
    [switch]$ValidateOnly,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ReleasePath)) {
    $ReleasePath = Join-Path $root 'deployment\agents\smart-submit-v1.json'
}

if (-not (Test-Path -LiteralPath $ReleasePath)) {
    throw "Missing Agent release manifest: $ReleasePath"
}
$registryPath = Join-Path $root 'deployment\agents\native-tool-registry.json'
$configPath = Join-Path $root 'deployment\librechat.yaml'
if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing native tool registry: $registryPath"
}
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing deployment config: $configPath"
}

function Get-RequiredText {
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Property,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $value = $Object.$Property
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        throw "Missing required Agent release field: $Path"
    }
    return [string]$value
}

function Get-StableObjectId {
    param([Parameter(Mandatory = $true)][string]$Seed)

    $sha1 = [Security.Cryptography.SHA1]::Create()
    try {
        $bytes = $sha1.ComputeHash([Text.Encoding]::UTF8.GetBytes($Seed))
        $hex = -join ($bytes | ForEach-Object { $_.ToString('x2') })
        return $hex.Substring(0, 24)
    } finally {
        $sha1.Dispose()
    }
}

function ConvertTo-MongoJson {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ($Value | ConvertTo-Json -Depth 20 -Compress)
}

$release = Get-Content -LiteralPath $ReleasePath -Raw -Encoding UTF8 | ConvertFrom-Json
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
if ((Get-RequiredText $release 'schema_version' 'schema_version') -ne 'agentos.agent-release.v1') {
    throw "Unsupported Agent release schema: $($release.schema_version)"
}

$agentId = Get-RequiredText $release 'agent_id' 'agent_id'
$businessAgentId = if ($release.PSObject.Properties.Name -contains 'business_agent_id') {
    Get-RequiredText $release 'business_agent_id' 'business_agent_id'
} else {
    $agentId
}
$displayName = Get-RequiredText $release 'display_name' 'display_name'
$businessVersion = Get-RequiredText $release 'business_version' 'business_version'
$publicationStatus = Get-RequiredText $release 'publication_status' 'publication_status'
$category = Get-RequiredText $release 'category' 'category'
$publisher = Get-RequiredText $release 'publisher' 'publisher'
$description = Get-RequiredText $release 'description' 'description'
$instructions = Get-RequiredText $release 'instructions' 'instructions'
$runtime = $release.runtime
$provider = Get-RequiredText $runtime 'provider' 'runtime.provider'
$model = Get-RequiredText $runtime 'model' 'runtime.model'
$reasoning = Get-RequiredText $runtime 'reasoning' 'runtime.reasoning'
$allowedModels = @($runtime.allowed_models | ForEach-Object { [string]$_ } | Where-Object { $_ })
if ($allowedModels.Count -eq 0) {
    throw 'runtime.allowed_models must contain at least one verified model.'
}
if ($model -notin $allowedModels) {
    throw 'runtime.model must be included in runtime.allowed_models.'
}

if ($publicationStatus -notin @('draft', 'pending_publish_validation', 'published', 'retired')) {
    throw "Unsupported publication_status: $publicationStatus"
}
if ((Get-RequiredText $registry 'schema_version' 'native-tool-registry.schema_version') -ne 'agentos.native-tool-registry.v1') {
    throw "Unsupported native tool registry schema: $($registry.schema_version)"
}

$configuredMcpIds = @($runtime.mcp_server_ids | ForEach-Object { [string]$_ } | Where-Object { $_ })
if ($configuredMcpIds.Count -eq 0) {
    throw 'runtime.mcp_server_ids must contain at least one MCP Server.'
}
$registryMcpIds = @($registry.mcp_servers.PSObject.Properties.Name)
foreach ($mcpId in $configuredMcpIds) {
    if ($mcpId -notin $registryMcpIds) {
        throw "MCP Server is not registered: $mcpId"
    }
    if ($configText -notmatch ('(?m)^\s+' + [regex]::Escape([string]$registry.mcp_servers.$mcpId.config_key) + ':\s*$')) {
        throw "MCP Server is not present in deployment/librechat.yaml: $mcpId"
    }
}

if ($agentId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Invalid Agent ID: $agentId"
}
if ($agentId -notmatch '^agent_') {
    throw "Persistent LibreChat Agent ID must start with agent_: $agentId"
}
if ($businessAgentId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Invalid business Agent ID: $businessAgentId"
}

$toolIds = @($runtime.tool_ids)
if ($toolIds.Count -eq 0) {
    throw 'runtime.tool_ids must contain at least one tool.'
}

$registeredContractTools = @($registry.contract_tools | ForEach-Object { [string]$_ })
$registeredNativeTools = @($registry.native_tools | ForEach-Object { [string]$_ })
$requestedContractTools = @($toolIds | ForEach-Object { [string]$_ })
$requestedContractSignature = (($requestedContractTools | Sort-Object) -join '|')
$registeredContractSignature = (($registeredContractTools | Sort-Object) -join '|')
if ($requestedContractSignature -ne $registeredContractSignature) {
    throw 'runtime.tool_ids must exactly match the registered Submit Flow contract tools.'
}

$nativeTools = [System.Collections.Generic.List[string]]::new()
foreach ($toolId in $toolIds) {
    if ([string]$toolId -notmatch '^submit_flow\.([A-Za-z0-9_]+)$') {
        throw "Unsupported Submit Flow tool identifier: $toolId"
    }
    $nativeTool = "{0}_mcp_submit-flow" -f $Matches[1]
    if ($nativeTool -notin $registeredNativeTools) {
        throw "Native MCP tool is not registered: $nativeTool"
    }
    if (-not $nativeTools.Contains($nativeTool)) {
        $nativeTools.Add($nativeTool)
    }
}

$skillNames = @($runtime.skill_ids | ForEach-Object { [string]$_ })
if ($skillNames.Count -eq 0) {
    throw 'runtime.skill_ids must contain at least one deployment Skill.'
}
$skillRoot = Join-Path $root 'deployment\skill'
foreach ($skillName in $skillNames) {
    if ($skillName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Invalid deployment Skill name: $skillName"
    }
    $skillPath = Join-Path (Join-Path $skillRoot $skillName) 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
        throw "Deployment Skill is missing SKILL.md: $skillName"
    }
    $skillText = Get-Content -LiteralPath $skillPath -Raw -Encoding UTF8
    if ($skillText -notmatch ('(?m)^name:\s*' + [regex]::Escape($skillName) + '\s*$')) {
        throw "Deployment Skill frontmatter name does not match its directory: $skillName"
    }
}
$skillIds = @($skillNames | ForEach-Object { Get-StableObjectId "deployment-skill:$($_)" })

$roleAliases = @{
    employee = 'USER'
    user = 'USER'
    admin = 'ADMIN'
}
$allowedRoles = @($release.employee_access.allowed_roles | ForEach-Object {
        $rawRole = ([string]$_).Trim()
        if ($roleAliases.ContainsKey($rawRole.ToLowerInvariant())) {
            $roleAliases[$rawRole.ToLowerInvariant()]
        } else {
            $rawRole.ToUpperInvariant()
        }
    } | Where-Object { $_ } | Sort-Object -Unique)
if ($allowedRoles.Count -eq 0) {
    throw 'employee_access.allowed_roles must contain at least one role.'
}

$releaseRecord = $release.release_record
$releaseId = Get-RequiredText $releaseRecord 'release_id' 'release_record.release_id'
$publishedAt = Get-RequiredText $releaseRecord 'published_at' 'release_record.published_at'
$acceptanceContract = Get-RequiredText $releaseRecord 'acceptance_contract' 'release_record.acceptance_contract'
$verificationTask = Get-RequiredText $releaseRecord 'verification_task' 'release_record.verification_task'

$agentSpec = [ordered]@{
    id = $agentId
    business_agent_id = $businessAgentId
    name = $displayName
    description = $description
    instructions = $instructions
    provider = $provider
    model = $model
    allowed_models = @($allowedModels)
    model_parameters = [ordered]@{
        model = $model
        allowed_models = @($allowedModels)
        reasoning_effort = $reasoning
    }
    tools = @($nativeTools)
    skills = @($skillIds)
    skills_enabled = [bool]$runtime.skills_enabled
    tool_kwargs = @()
    agent_ids = @()
    edges = @()
    conversation_starters = @()
    category = $category
    is_promoted = $false
    publication_status = $publicationStatus
    business_version = $businessVersion
    allowed_roles = @($allowedRoles)
    release_metadata = [ordered]@{
        release_id = $releaseId
        business_version = $businessVersion
        published_at = $publishedAt
        publisher = $publisher
        acceptance_contract = $acceptanceContract
        verification_task = $verificationTask
    }
    mcpServerNames = @($configuredMcpIds)
    authorName = $publisher
    versions = @()
}

$agentSpec.versions = @([ordered]@{
        name = $displayName
        description = $description
        instructions = $instructions
        provider = $provider
        model = $model
        model_parameters = $agentSpec.model_parameters
        tools = @($nativeTools)
        skills = @($skillIds)
        skills_enabled = [bool]$runtime.skills_enabled
        publication_status = $publicationStatus
        business_version = $businessVersion
        allowed_roles = @($allowedRoles)
        id = $agentId
    })

if ([bool]$runtime.allow_model_override -or [bool]$runtime.allow_reasoning_override -or [bool]$runtime.allow_tool_override) {
    throw 'Locked Agent release must disable model, reasoning, and tool overrides.'
}
if (@($runtime.tool_ids).Count -ne $registeredContractTools.Count) {
    throw "The release must expose exactly $($registeredContractTools.Count) registered tools."
}
if (@($release.risk_policy.requires_human_confirmation) -notcontains 'submit_flow.confirm_task') {
    throw 'The V1 Submit Flow release must retain human confirmation for confirm_task.'
}

if (-not $Quiet) {
    Write-Host "Validated Agent release: $agentId ($displayName), tools=$($nativeTools.Count), skills=$($skillNames.Count)"
}

if ($ValidateOnly) {
    return
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker is required to synchronize Agent data.'
}

$agentJson = ConvertTo-MongoJson $agentSpec
$mongoScript = @"
const spec = $agentJson;
const now = new Date();
const owner = db.users.find({ role: 'ADMIN' }).sort({ username: 1, _id: 1 }).limit(1).next();
if (!owner) throw new Error('No ADMIN user exists; cannot assign the managed Agent owner.');
const viewerRole = db.accessroles.findOne({ accessRoleId: 'agent_viewer', resourceType: 'agent' });
if (!viewerRole) throw new Error('The native agent_viewer role is missing.');
const existing = db.agents.findOne({ id: spec.id }) || db.agents.findOne({ id: spec.business_agent_id });
const previousId = existing ? existing._id : null;
spec.author = owner._id;
spec.versions.forEach((version) => version.author = owner._id);
spec.updatedAt = now;
spec.authorName = spec.authorName || owner.username || owner.email;
spec.versions.forEach((version) => { version.updatedAt = now; version.createdAt = now; });
if (existing) {
  db.agents.updateOne({ _id: existing._id }, { `$set: spec });
} else {
  spec.createdAt = now;
  db.agents.insertOne(spec);
}
const agent = db.agents.findOne({ id: spec.id });
if (!agent) throw new Error('Managed Agent was not persisted with its native platform ID.');
db.conversations.updateMany({ agent_id: spec.business_agent_id }, { `$set: { agent_id: spec.id } });
db.agents.deleteMany({ id: spec.business_agent_id, _id: { `$ne: agent._id } });
if (spec.publication_status === 'published') {
  db.aclentries.updateOne(
    { principalType: 'public', resourceType: 'agent', resourceId: agent._id },
    {
      `$set: {
        permBits: viewerRole.permBits,
        roleId: viewerRole._id,
        grantedBy: owner._id,
        grantedAt: now,
        updatedAt: now
      },
      `$setOnInsert: { createdAt: now }
    },
    { upsert: true }
  );
} else {
  db.aclentries.deleteOne({ principalType: 'public', resourceType: 'agent', resourceId: agent._id });
}
printjson({
  action: existing ? 'updated' : 'created',
  agentId: agent.id,
  mongoId: agent._id.toString(),
  owner: owner.username || owner.email,
  publicationStatus: agent.publication_status,
  publicView: spec.publication_status === 'published',
  previousMongoId: previousId ? previousId.toString() : null,
  tools: agent.tools,
  skills: agent.skills
});
"@

if ($PSCmdlet.ShouldProcess("MongoDB $Database/$agentId", 'synchronize managed Agent and public VIEW ACL')) {
    # Windows PowerShell uses the system code page for native-process stdin by
    # default. The release manifest contains Chinese text, so send the script
    # to mongosh as UTF-8 to keep persisted Agent metadata intact.
    $previousOutputEncoding = $OutputEncoding
    try {
        $OutputEncoding = [Text.UTF8Encoding]::new($false)
        $mongoScript | docker exec -i $MongoContainer mongosh --quiet $Database
    } finally {
        $OutputEncoding = $previousOutputEncoding
    }
    if ($LASTEXITCODE -ne 0) {
        throw "MongoDB Agent synchronization failed with exit code $LASTEXITCODE."
    }
}
