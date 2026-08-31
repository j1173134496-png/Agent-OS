[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$brandingPath = Join-Path $root 'source\librechat-maintained\client\public\assets'
$sourceLogoPath = Join-Path $root 'Logo.png'
$logoMarkPath = Join-Path $brandingPath 'logo-mark.png'
$brandShort = (-join ([char[]](0x7ACB, 0x80FD, 0x6D3E)))
$brandName = $brandShort + ' Agent OS'

if (-not (Test-Path -LiteralPath $brandingPath)) {
    New-Item -ItemType Directory -Path $brandingPath -Force | Out-Null
}

Add-Type -AssemblyName System.Drawing

function New-LogoMark {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $sourceLogoPath)) {
        throw "Missing source logo: $sourceLogoPath"
    }

    $source = [System.Drawing.Bitmap]::FromFile($sourceLogoPath)
    $bitmap = New-Object System.Drawing.Bitmap(512, 512)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.Clear([System.Drawing.Color]::White)
        # Crop the robot and lightning mark above the source wordmark.
        $crop = [System.Drawing.Rectangle]::new(120, 55, 1010, 900)
        $target = [System.Drawing.Rectangle]::new(0, 0, 512, 512)
        $graphics.DrawImage($source, $target, $crop, [System.Drawing.GraphicsUnit]::Pixel)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        $source.Dispose()
    }
}

function New-BrandLogo {
    param([Parameter(Mandatory = $true)][string]$Path)

    $encodedMark = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($logoMarkPath))
    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 128" role="img" aria-labelledby="title desc">
  <title id="title">$brandName</title>
  <desc id="desc">$brandName brand mark</desc>
  <rect width="300" height="128" rx="20" fill="#ffffff"/>
  <image href="data:image/png;base64,$encodedMark" x="10" y="8" width="112" height="112" preserveAspectRatio="xMidYMid meet"/>
  <text x="145" y="61" fill="#ff6a00" font-family="Microsoft YaHei, PingFang SC, Arial, sans-serif" font-size="32" font-weight="700">$brandShort</text>
  <text x="145" y="98" fill="#252525" font-family="Arial, Helvetica, sans-serif" font-size="29" font-weight="700" letter-spacing="1">Agent OS</text>
</svg>
"@
    [System.IO.File]::WriteAllText($Path, $svg, [System.Text.UTF8Encoding]::new($false))
}

function New-BrandFavicon {
    param([Parameter(Mandatory = $true)][string]$Path)

    $encodedMark = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($logoMarkPath))
    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-label="$brandName">
  <rect width="64" height="64" rx="14" fill="#ffffff"/>
  <image href="data:image/png;base64,$encodedMark" x="3" y="3" width="58" height="58" preserveAspectRatio="xMidYMid meet"/>
</svg>
"@
    [System.IO.File]::WriteAllText($Path, $svg, [System.Text.UTF8Encoding]::new($false))
}

function New-BrandIcon {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$Size,
        [switch]$Maskable
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        return
    }

    $mark = [System.Drawing.Bitmap]::FromFile($logoMarkPath)
    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.Clear([System.Drawing.Color]::White)

        $inset = if ($Maskable) { [int]($Size * 0.12) } else { [int]($Size * 0.04) }
        $shape = [System.Drawing.Rectangle]::new($inset, $inset, ($Size - (2 * $inset)), ($Size - (2 * $inset)))
        $graphics.DrawImage($mark, $shape)
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        $mark.Dispose()
    }
}

New-LogoMark -Path $logoMarkPath
New-BrandLogo -Path (Join-Path $brandingPath 'logo.svg')
New-BrandFavicon -Path (Join-Path $brandingPath 'favicon.svg')
New-BrandIcon -Path (Join-Path $brandingPath 'favicon-16x16.png') -Size 16
New-BrandIcon -Path (Join-Path $brandingPath 'favicon-32x32.png') -Size 32
New-BrandIcon -Path (Join-Path $brandingPath 'apple-touch-icon-180x180.png') -Size 180
New-BrandIcon -Path (Join-Path $brandingPath 'icon-192x192.png') -Size 192
New-BrandIcon -Path (Join-Path $brandingPath 'maskable-icon.png') -Size 512 -Maskable

Write-Host "Brand assets ready for the V0.3.1 source build: $brandingPath"
