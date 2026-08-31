[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$templatePath = Join-Path $root '.env.example'
$envPath = Join-Path $root '.env'

if ((Test-Path $envPath) -and -not $Force) {
    throw "The private .env already exists. Use -Force only when you intend to replace it."
}

function New-Secret {
    param([int]$Bytes = 32)

    $buffer = New-Object byte[] $Bytes
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($buffer)
    } finally {
        $generator.Dispose()
    }
    return ([BitConverter]::ToString($buffer)).Replace('-', '').ToLowerInvariant()
}

$content = Get-Content -Raw -LiteralPath $templatePath
$content = $content.Replace('__GENERATE_MEILI_MASTER_KEY__', (New-Secret 32))
$content = $content.Replace('__GENERATE_VECTORDB_PASSWORD__', (New-Secret 24))
$content = $content.Replace('__GENERATE_JWT_SECRET__', (New-Secret 32))
$content = $content.Replace('__GENERATE_JWT_REFRESH_SECRET__', (New-Secret 32))

[System.IO.File]::WriteAllText($envPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "Created private environment file: $envPath"
