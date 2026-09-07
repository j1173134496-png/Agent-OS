[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$MongoContainer = 'agentos-mongodb',
    [string]$Database = 'LibreChat',
    [string]$ReportPath,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $root 'deployment\runtime\v0.3.2\policy-sync-report.json'
}

$expected = [ordered]@{
    ADMIN = [ordered]@{
        AGENTS = [ordered]@{ USE = $true; CREATE = $true; SHARE = $false; SHARE_PUBLIC = $false }
        SKILLS = [ordered]@{ USE = $true; CREATE = $true; SHARE = $false; SHARE_PUBLIC = $false }
        MARKETPLACE = [ordered]@{ USE = $true }
    }
    USER = [ordered]@{
        AGENTS = [ordered]@{ USE = $true; CREATE = $false; SHARE = $false; SHARE_PUBLIC = $false }
        SKILLS = [ordered]@{ USE = $true; CREATE = $false; SHARE = $false; SHARE_PUBLIC = $false }
        MARKETPLACE = [ordered]@{ USE = $true }
    }
}

if ($ValidateOnly) {
    $report = [ordered]@{
        schema_version = 'agentos.v0.3.2.policy-sync-report.v1'
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        status = 'VALIDATED'
        validate_only = $true
        expected = $expected
    }
    $reportDir = Split-Path -Parent $ReportPath
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host "Validated V0.3.2 role policy contract: $ReportPath"
    return
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker is required to synchronize the V0.3.2 role policy.'
}

$mongoScript = @"
const expected = {
  ADMIN: {
    AGENTS: { USE: true, CREATE: true, SHARE: false, SHARE_PUBLIC: false },
    SKILLS: { USE: true, CREATE: true, SHARE: false, SHARE_PUBLIC: false },
    MARKETPLACE: { USE: true }
  },
  USER: {
    AGENTS: { USE: true, CREATE: false, SHARE: false, SHARE_PUBLIC: false },
    SKILLS: { USE: true, CREATE: false, SHARE: false, SHARE_PUBLIC: false },
    MARKETPLACE: { USE: true }
  }
};
const now = new Date();
const results = [];
for (const name of ['ADMIN', 'USER']) {
  if (!db.roles.findOne({ name })) throw new Error('Missing required role: ' + name);
  db.roles.updateOne(
    { name },
    { `$set: {
      'permissions.AGENTS': expected[name].AGENTS,
      'permissions.SKILLS': expected[name].SKILLS,
      'permissions.MARKETPLACE': expected[name].MARKETPLACE,
      updatedAt: now
    } }
  );
  const role = db.roles.findOne({ name }, { name: 1, permissions: 1, updatedAt: 1 });
  results.push({ name: role.name, permissions: {
    AGENTS: role.permissions.AGENTS,
    SKILLS: role.permissions.SKILLS,
    MARKETPLACE: role.permissions.MARKETPLACE
  }, updatedAt: role.updatedAt || null });
}
print(EJSON.stringify({ schema_version: 'agentos.v0.3.2.policy-sync-report.v1', status: 'APPLIED', generated_at: now.toISOString(), roles: results }));
"@

if (-not $PSCmdlet.ShouldProcess("MongoDB $Database", 'synchronize V0.3.2 role policy')) {
    return
}

$previousOutputEncoding = $OutputEncoding
try {
    $OutputEncoding = [Text.UTF8Encoding]::new($false)
    $mongoOutput = @($mongoScript | docker exec -i $MongoContainer mongosh --quiet $Database)
} finally {
    $OutputEncoding = $previousOutputEncoding
}
if ($LASTEXITCODE -ne 0) {
    throw "MongoDB V0.3.2 policy synchronization failed with exit code $LASTEXITCODE."
}

$mongoText = ($mongoOutput | ForEach-Object { [string]$_ }) -join "`n"
$jsonMatch = [regex]::Match(
    $mongoText,
    '(?s)(\{"schema_version":"agentos\.v0\.3\.2\.policy-sync-report\.v1".*?\]\})'
)
if (-not $jsonMatch.Success) {
    throw "MongoDB policy synchronization returned no JSON report. Output: $mongoText"
}
$reportDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$jsonMatch.Groups[1].Value | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "Applied V0.3.2 role policy: $ReportPath"
