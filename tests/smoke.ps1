# Windows adapter for the smoke contract (tests/smoke.contract).
#
# Reads the contract, executes each check inside the container. Must be
# invoked with the tests/ directory mounted at C:\tests inside the container,
# e.g.:
#   docker run --rm -v "$PWD\tests:C:\tests" <image> powershell -File C:\tests\smoke.ps1
#
# Override the contract path via SMOKE_CONTRACT env var if needed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$contract = $env:SMOKE_CONTRACT
if (-not $contract) { $contract = 'C:\tests\smoke.contract' }

if (-not (Test-Path $contract)) {
    Write-Host "Contract not found: $contract"
    exit 2
}

Write-Host "Smoke contract: $contract"
Write-Host ""

Get-Content $contract | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }

    $parts = $line -split ' ',2
    $kind = $parts[0]
    $rest = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }

    switch ($kind) {
        'exists' {
            $p = Get-Command $rest -ErrorAction SilentlyContinue
            if (-not $p) { Write-Host "FAIL: $rest not on PATH"; exit 1 }
            Write-Host "OK: $rest -> $($p.Source)"
        }
        'succeeds' {
            # Use cmd /c so native commands' exit codes are captured cleanly.
            cmd /c $rest "`$null" 2>`$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "FAIL: command exited ${LASTEXITCODE}: $rest"
                exit 1
            }
            Write-Host "OK: $rest"
        }
        'best_effort' {
            try {
                $out = cmd /c $rest 2>`$null
                $out | Select-Object -First 3 | ForEach-Object { Write-Host $_ }
            } catch {
                # Swallow; best-effort.
            }
        }
        default {
            Write-Host "FAIL: unknown check type: $kind"
            exit 1
        }
    }
}

Write-Host ""
Write-Host "Smoke test passed."
