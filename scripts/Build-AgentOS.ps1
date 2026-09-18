[CmdletBinding()]
param(
    [string]$Tag = 'v0.3.1',
    [string]$ImageRepository = 'agentos/librechat'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourcePath = Join-Path $root 'source\librechat-maintained'
$composePath = Join-Path $root 'deployment\compose.yaml'

if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Missing source tree: $sourcePath" }

$image = "$ImageRepository`:$Tag"
& docker build --file (Join-Path $sourcePath 'Dockerfile') --tag $image $sourcePath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$digest = [string](& docker image inspect $image --format '{{index .RepoDigests 0}}')
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($digest) -or $digest -notmatch '@sha256:[a-f0-9]{64}$') {
    throw "Docker did not expose a content digest for $image."
}

$composeText = [IO.File]::ReadAllText($composePath)
$imagePattern = '(?m)(^\s*image:\s*(?:\$\{AGENTOS_API_IMAGE:-)?' + [regex]::Escape($ImageRepository) + ')(@sha256:[a-f0-9]{64}|:[^\s}]+)'
$digestRef = $digest.Substring($digest.IndexOf('@'))
$updated = [regex]::Replace($composeText, $imagePattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + $digestRef }, 1)
if ($updated -eq $composeText) { throw "Could not update the API image reference in $composePath." }
[IO.File]::WriteAllText($composePath, $updated, [Text.UTF8Encoding]::new($false))

Write-Host "Built $image and pinned Compose to $digest"
