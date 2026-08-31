[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
    $matches = @(& rg --hidden --line-number --no-heading `
        -g '!.git/**' `
        -g '!.env' `
        -g '!deployment/data/**' `
        -g '!deployment/uploads/**' `
        -g '!deployment/logs/**' `
        '(sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|Authorization\s*[:=]\s*["'']?Bearer\s+[A-Za-z0-9._~+/=-]{20,})' . 2>$null)
    if ($matches.Count -gt 0) {
        $matches | ForEach-Object { Write-Output $_ }
        Write-Error 'Potential secret material found.'
        exit 1
    }
    Write-Host 'Secret scan: PASS'
} finally {
    Pop-Location
}
