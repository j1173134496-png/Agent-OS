[CmdletBinding()]
param(
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3\static-report.json'
}

$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'FAIL', 'BLOCKED')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    $checks.Add([ordered]@{ name = $Name; status = $Status; detail = $Detail })
}

function Assert-Check {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )
    if ($Condition) { Add-Check -Name $Name -Status 'PASS' -Detail $Detail }
    else { Add-Check -Name $Name -Status 'FAIL' -Detail $Detail }
}

try {
    $rollbackRoot = Join-Path $root 'deployment\rollback\v0.3.0'
    $schemaPath = Join-Path $rollbackRoot 'plugins\manifest.schema.json'
    $catalogPath = Join-Path $rollbackRoot 'plugins\catalog.json'
    $schema = [System.IO.File]::ReadAllText($schemaPath) | ConvertFrom-Json
    $catalog = [System.IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json
    $requiredFields = @($schema.required)
    $plugins = @($catalog.plugins)

    Assert-Check ($catalog.schema_version -eq 'agentos.plugin-catalog.v1') 'catalog_schema' 'Catalog schema version is supported.'
    Assert-Check (($plugins | Measure-Object).Count -ge 1) 'catalog_non_empty' 'At least one plugin is registered.'
    Assert-Check ((@($plugins.id) | Select-Object -Unique).Count -eq $plugins.Count) 'catalog_unique_ids' 'Plugin IDs are unique.'

    foreach ($plugin in $plugins) {
        $missing = @($requiredFields | Where-Object { -not $plugin.PSObject.Properties.Name.Contains($_) })
        Assert-Check (($missing.Count -eq 0) -and (($plugin.PSObject.Properties.Name | Where-Object { $requiredFields -notcontains $_ }).Count -le 3)) `
            "manifest_$($plugin.id)" "Manifest has required fields and only declared optional model metadata."
        Assert-Check ((@($plugin.allowedTools | Where-Object { $_ -notin @('agentos_demo', 'image_gen_oai', 'image_edit_oai') }).Count -eq 0)) `
            "tools_$($plugin.id)" "Manifest tools are restricted to the AgentOS allowlist."
    }

    $runtimeFiles = @(
        (Join-Path $rollbackRoot 'agentos-runtime\catalog.js'),
        (Join-Path $rollbackRoot 'agentos-runtime\capabilityGate.js'),
        (Join-Path $rollbackRoot 'agentos-runtime\AgentOSDemo.js'),
        (Join-Path $rollbackRoot 'agentos-runtime\pluginRouter.js'),
        (Join-Path $root 'deployment\overrides\OpenAIImageTools.js')
    )
    $dangerousCodePattern = '(?i)child_process|execFile|spawn\(|fork\(|powershell\.exe|cmd\.exe|process\.system|runtime_root|absolute_path'
    $dangerousFiles = @($runtimeFiles | Where-Object {
            (Test-Path -LiteralPath $_) -and ([regex]::IsMatch([System.IO.File]::ReadAllText($_), $dangerousCodePattern))
        })
    Assert-Check ($dangerousFiles.Count -eq 0) 'no_free_execution_entry' 'AgentOS runtime has no shell, process, or arbitrary-path execution entry.'

    $gateText = [System.IO.File]::ReadAllText((Join-Path $rollbackRoot 'agentos-runtime\capabilityGate.js'))
    Assert-Check ($gateText.Contains('agent.tools = tools') -and $gateText.Contains('delete req.body.tools') -and $gateText.Contains('delete req.body.mcpServers')) `
        'capability_gate_strips_client_tools' 'Capability Gate replaces client tool input with server-side allowlisted tools.'

    $frontEndText = [System.IO.File]::ReadAllText((Join-Path $rollbackRoot 'branding\agentos-plugins.js'))
    Assert-Check ($frontEndText.Contains('agentos_plugin_ids') -and $frontEndText.Contains('persistSelection') -and $frontEndText.Contains('carryNewConversationDraft') -and $frontEndText.Contains('!draft.length')) `
        'frontend_selection_contract' 'Frontend sends session selection and carries only the new-chat draft into its first real conversation.'
    $syncRouteMatch = [regex]::Match($frontEndText, 'function syncRoute\(\) \{[\s\S]*?\n  \}')
    Assert-Check ($syncRouteMatch.Success -and -not $syncRouteMatch.Value.Contains('carryNewConversationDraft')) `
        'frontend_route_isolation' 'Normal route changes load stored selections instead of migrating the new-chat draft.'

    $nodeProbe = @'
require('module-alias')({ base: '/app/api' });
const catalog = require('/app/agentos/runtime/catalog');
const user = { role: 'user' };
const guest = { role: 'guest' };
const result = {
  catalog: catalog.getCatalog().plugins.map((plugin) => plugin.id),
  userPlugins: catalog.getAuthorizedPlugins(user).map((plugin) => plugin.id),
  guestPlugins: catalog.getAuthorizedPlugins(guest).map((plugin) => plugin.id),
  noPluginTools: catalog.getToolsForPlugins([], user),
  demoTools: catalog.getToolsForPlugins(['agentos-demo'], user),
  imageTools: catalog.getToolsForPlugins(['agentos-image'], user),
  demoSkills: catalog.getSkillsForPlugins(['agentos-demo'], user).map((skill) => skill.id),
};
process.stdout.write(JSON.stringify(result));
process.exit(0);
'@
    $probeOutput = (& docker exec agentos-api node -e $nodeProbe 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        Add-Check 'runtime_allowlist_probe' 'FAIL' ('Container runtime probe failed: ' + $probeOutput)
    } else {
        $probe = $probeOutput | ConvertFrom-Json
        Assert-Check (($probe.noPluginTools | Measure-Object).Count -eq 0) 'runtime_no_plugin_tools' 'No selected plugin produces zero tools.'
        Assert-Check ((@($probe.demoTools) -join ',') -eq 'agentos_demo') 'runtime_demo_allowlist' 'Demo selection exposes only agentos_demo.'
        Assert-Check ((@($probe.imageTools) -join ',') -eq 'image_gen_oai,image_edit_oai') 'runtime_image_allowlist' 'Image selection exposes only image tools.'
        Assert-Check (($probe.guestPlugins | Measure-Object).Count -eq 0) 'runtime_role_filter' 'An unrecognized role receives no authorized plugins.'
        Assert-Check ((@($probe.demoSkills) -join ',') -eq 'agentos-demo') 'runtime_skill_allowlist' 'Demo selection loads only its declared Skill.'
    }
} catch {
    Add-Check 'static_harness' 'FAIL' $_.Exception.Message
}

$hasFailure = @($checks | Where-Object { $_.status -eq 'FAIL' }).Count -gt 0
$hasBlocked = @($checks | Where-Object { $_.status -eq 'BLOCKED' }).Count -gt 0
$gate = if ($hasFailure) { 'FAIL' } elseif ($hasBlocked) { 'BLOCKED' } else { 'PASS' }
$report = [ordered]@{
    schema_version = 'agentos.v0.3.static-report.v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    checks = $checks
    gate = $gate
}

$parent = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[System.IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

Write-Host "V0.3 static gate: $gate. Report: $ReportPath"
if ($gate -eq 'FAIL') { exit 1 }
if ($gate -eq 'BLOCKED') { exit 2 }
exit 0
