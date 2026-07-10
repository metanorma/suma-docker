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
$out = suma --version 2>&1 | Select-Object -First 3
$out | ForEach-Object { Write-Host $_ }

# eengine: SBCL binary, no clean --version flag on Windows. Try --help
# but accept failure (best-effort only — the binaries' presence on PATH
# is the gate that matters; metanorma/suma actually invoke them at build
# time, so a runtime crash would surface there).
Write-Host ""
Write-Host "=== eengine (best-effort) ==="
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'eengine'
    $psi.Arguments = '--eehelp'
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    if (-not $proc.WaitForExit(5000)) {
        Write-Host "(timed out after 5s — killed)"
        $proc.Kill()
    } else {
        $proc.StandardOutput.ReadLine() | Write-Host
    }
} catch {
    Write-Host "(no output)"
}

Write-Host ""
Write-Host "=== eep (best-effort) ==="
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'eep'
    $psi.Arguments = '-h'
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    if (-not $proc.WaitForExit(5000)) {
        Write-Host "(timed out after 5s — killed)"
        $proc.Kill()
    } else {
        $proc.StandardOutput.ReadLine() | Write-Host
    }
} catch {
    Write-Host "(no output)"
}

Write-Host ""
Write-Host "Smoke test passed."
