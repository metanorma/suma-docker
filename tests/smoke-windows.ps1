# Windows wrapper for the smoke test.
#
# The Linux side has tests/smoke.sh — a host-side wrapper that takes an
# image tag and runs docker. The workflow doesn't need to know how the
# smoke test runs inside the container.
#
# The Windows side leaked those facts into the workflow YAML:
#   docker run --rm -v "$env:GITHUB_WORKSPACE\tests:C:\tests" $tag powershell -File C:\tests\smoke.ps1
# That's three adapter facts (PowerShell runtime, C:\tests mount path,
# smoke.ps1 filename) leaking into every Windows job.
#
# This wrapper restores symmetry: workflow just calls
#   ./tests/smoke-windows.ps1 -Image <tag>
# and the wrapper handles docker run + mount + smoke.ps1 invocation.
#
# Usage:
#   tests/smoke-windows.ps1 -Image <tag>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Image
)

$ErrorActionPreference = 'Stop'

if (-not $env:GITHUB_WORKSPACE) {
    # Allow local invocation by falling back to the current directory.
    $env:GITHUB_WORKSPACE = (Get-Location).Path
}

$testsDir = Join-Path $env:GITHUB_WORKSPACE 'tests'

if (-not (Test-Path (Join-Path $testsDir 'smoke.ps1'))) {
    Write-Host "smoke.ps1 not found at $testsDir"
    exit 2
}

Write-Host "Smoke-testing Windows image: $Image"
Write-Host "Mounting $testsDir at C:\tests"
Write-Host ""

docker run --rm -v "${testsDir}:C:\tests" $Image powershell -File C:\tests\smoke.ps1
