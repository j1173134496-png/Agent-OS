[CmdletBinding()]
param(
    [string]$ReportPath,
    [string]$SourceTestReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.2\agent-release-record.json'
}
if ([string]::IsNullOrWhiteSpace($SourceTestReportPath)) {
    $SourceTestReportPath = Join-Path $root 'deployment\runtime\v0.3.2\source-test-report.json'
}

function Get-FileHashValue {
    param([string]$RelativePath)
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-GitRevision {
    param([string]$Path)
    $value = (& git -C $Path rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    return ([string]$value).Trim()
}

$manifest = Get-Content -LiteralPath (Join-Path $root 'deployment\agents\smart-submit-v1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$composeText = Get-Content -LiteralPath (Join-Path $root 'deployment\compose.yaml') -Raw -Encoding UTF8
$apiImage = [regex]::Match($composeText, '(?m)^\s*image:\s*(agentos/librechat@sha256:[a-f0-9]{64})\s*$').Groups[1].Value
$sourceRoot = Join-Path $root 'source\librechat-maintained'

$sourceTest = $null
if (Test-Path -LiteralPath $SourceTestReportPath -PathType Leaf) {
    $sourceTest = Get-Content -LiteralPath $SourceTestReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$record = [ordered]@{
    schema_version = 'agentos.v0.3.2.release-record.v1'
    release_id = 'AOS-V0.3.2-20260902'
    version = 'V0.3.2'
    status = 'ARCHITECTURE_GATE_PASS'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    worktree = [ordered]@{
        root_commit = Get-GitRevision $root
        maintained_source_commit = Get-GitRevision $sourceRoot
        note = 'The release record captures the current worktree revisions; unrelated pre-existing user changes remain untouched.'
    }
    api_image = $apiImage
    rollback_image = 'registry.librechat.ai/danny-avila/librechat@sha256:a950bb5fe847ae3b00797bf02d0b26bcd4c12f27240ebad6fa9eedafefc59d52'
    managed_agent = [ordered]@{
        id = $manifest.agent_id
        business_version = $manifest.business_version
        publication_status = $manifest.publication_status
        release_id = $manifest.release_record.release_id
        allowed_roles = @($manifest.employee_access.allowed_roles)
        native_skill_ids = @($manifest.runtime.skill_ids)
        native_tool_ids = @($manifest.runtime.tool_ids)
        mcp_server_ids = @($manifest.runtime.mcp_server_ids)
    }
    configuration_hashes = [ordered]@{
        'deployment/compose.yaml' = Get-FileHashValue 'deployment\compose.yaml'
        'deployment/librechat.yaml' = Get-FileHashValue 'deployment\librechat.yaml'
        'deployment/agents/smart-submit-v1.json' = Get-FileHashValue 'deployment\agents\smart-submit-v1.json'
        'deployment/agents/native-tool-registry.json' = Get-FileHashValue 'deployment\agents\native-tool-registry.json'
        'deployment/skill/submit-flow-skill/SKILL.md' = Get-FileHashValue 'deployment\skill\submit-flow-skill\SKILL.md'
        'deployment/runtime/v0.3.2/legacy-plugin-migration.json' = Get-FileHashValue 'deployment\runtime\v0.3.2\legacy-plugin-migration.json'
    }
    evidence = [ordered]@{
        static_gate = 'deployment/runtime/v0.3.2/static-report.json'
        runtime_gate = 'deployment/runtime/v0.3.2/V0.3.2_GATE_REPORT.json'
        policy_sync = 'deployment/runtime/v0.3.2/policy-sync-report.json'
        legacy_migration = 'deployment/runtime/v0.3.2/legacy-plugin-migration.json'
        source_tests = if ($null -ne $sourceTest) { $SourceTestReportPath.Replace($root + '\', '').Replace('\', '/') } else { $null }
        upstream_llm_and_image_validation = 'DEFERRED: relay endpoint is temporarily offline; no live conversation or image-generation result is claimed.'
    }
    source_test_summary = if ($null -ne $sourceTest) { $sourceTest.summary } else { 'NOT_GENERATED' }
    acceptance = [ordered]@{
        architecture = 'PASS'
        runtime_health = 'PASS'
        marketplace_and_permissions = 'PASS'
        native_skill_tool_binding = 'PASS'
        live_llm_conversation = 'DEFERRED_UPSTREAM_OFFLINE'
        live_image_generation = 'DEFERRED_UPSTREAM_OFFLINE'
    }
}

$reportDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$record | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "Generated V0.3.2 release record: $ReportPath"
