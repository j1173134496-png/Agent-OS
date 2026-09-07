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

    # LibreChat includes explicit credential-shaped values in unit-test fixtures.
    # Ignore only those named placeholders; never suppress arbitrary test files.
    $fixturePlaceholder = '(exchanged_graph_token|resolved-graph-token|resolved-graph-api-token|actual-api-key-value|default-from-env-key|static-gateway-token)'
    $matches = @($matches | Where-Object {
        $line = [string]$_
        $isKnownBearerFixture = $line -match '(\.spec\.|\.test\.|__tests__)' -and $line -match $fixturePlaceholder
        $isKnownPrivateKeyFixture = $line -match '(cloudfront\.test\.ts|cloudfront-cookies\.test\.ts)' -and $line -match 'BEGIN RSA PRIVATE KEY'
        $isScannerDefinition = $line -match '^\.\\scripts\\Secret-Scan-AgentOS\.ps1:'
        -not ($isKnownBearerFixture -or $isKnownPrivateKeyFixture -or $isScannerDefinition)
    })
    if ($matches.Count -gt 0) {
        $matches | ForEach-Object { Write-Output $_ }
        Write-Error 'Potential secret material found.'
        exit 1
    }
    Write-Host 'Secret scan: PASS'
} finally {
    Pop-Location
}
