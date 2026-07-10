# PowerShell smoke test for the Windows image.
# Verifies eengine, eep, metanorma, and suma are on PATH and that
# metanorma/suma respond to --version. Catches install-layer failures
# and Ruby regressions on the Windows side.
#
# Usage (inside the container):
#   powershell -File C:\tests\smoke.ps1
#
# Or from the host via docker:
#   docker run --rm -v "$PWD\tests:C:\tests" <image> powershell -File C:\tests\smoke.ps1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

Write-Host "=== Checking binaries on PATH ==="
foreach ($cmd in @('eengine','eep','metanorma','suma')) {
    $p = Get-Command $cmd -ErrorAction SilentlyContinue
    if (-not $p) {
        Write-Host "MISSING: $cmd"
        exit 1
    }
    Write-Host "OK: $cmd -> $($p.Source)"
}

Write-Host ""
Write-Host "=== metanorma --version ==="
metanorma --version

Write-Host ""
Write-Host "=== suma --version ==="
suma --version 2>&1 | Select-Object -First 3 | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Smoke test passed."
