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
            # Use Start-Process to fully detach stdout/stderr from PowerShell.
            # Native commands (like metanorma) write deprecation warnings to
            # stderr; PowerShell with ErrorActionPreference=Stop treats that
            # as fatal. Redirecting both streams to NUL inside cmd avoids it.
            $proc = Start-Process -FilePath "cmd" -ArgumentList "/c $rest >nul 2>nul" -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Write-Host "FAIL: command exited $($proc.ExitCode): $rest"
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
