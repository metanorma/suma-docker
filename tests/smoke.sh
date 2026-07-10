#!/usr/bin/env bash
# Smoke test: verify eengine, eep, metanorma, and suma are on PATH and
# respond to --version / --help. Catches install-layer failures and
# Ruby/glibc regressions.
#
# Usage: tests/smoke.sh <image>
set -euo pipefail

IMAGE="${1:?Usage: $0 <image>}"
echo "Smoke-testing image: ${IMAGE}"

# shellcheck disable=SC2016
docker run --rm "${IMAGE}" bash -c '
  set -e
  echo "=== Checking binaries on PATH ==="
  for cmd in eengine eep metanorma suma; do
    command -v "$cmd" >/dev/null || { echo "MISSING: $cmd"; exit 1; }
    echo "OK: $cmd -> $(command -v "$cmd")"
  done
  echo
  echo "=== metanorma --version ==="
  metanorma --version
  echo
  echo "=== suma --help (first 3 lines) ==="
  suma --help 2>&1 | head -3
  echo
  echo "=== eengine --version (best-effort, 5s timeout) ==="
  timeout 5 eengine --version || timeout 5 eengine --help || echo "(no output)"
  echo
  echo "=== eep --help (best-effort, 5s timeout) ==="
  timeout 5 eep --help || timeout 5 eep -h || echo "(no output)"
'

echo "Smoke test passed."
