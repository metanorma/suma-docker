#!/usr/bin/env bash
# Linux adapter for the smoke contract (tests/smoke.contract).
#
# Reads the contract, executes each check inside the image via `docker run`,
# exits non-zero if any check fails.
#
# Usage: tests/smoke.sh <image> [<contract-path>]
#   <image>           Docker image to test (required)
#   <contract-path>   Path to contract file (default: tests/smoke.contract)
set -euo pipefail

IMAGE="${1:?Usage: $0 <image> [<contract-path>]}"
CONTRACT="${2:-tests/smoke.contract}"

if [ ! -f "$CONTRACT" ]; then
    echo "Contract not found: $CONTRACT" >&2
    exit 2
fi

echo "Smoke-testing image: ${IMAGE}"
echo "Contract: ${CONTRACT}"
echo

# Pipe the contract into the container via stdin. The container's bash
# reads each line and dispatches by check type. Nothing is mounted.
# shellcheck disable=SC2016
docker run --rm -i "${IMAGE}" bash -c '
  set -e
  while read -r kind args; do
    case "$kind" in
      ""|\#*) continue ;;
      exists)
        # shellcheck disable=SC2086
        command -v $args >/dev/null 2>&1 || { echo "FAIL: $args not on PATH"; exit 1; }
        # shellcheck disable=SC2086
        echo "OK: $args -> $(command -v $args)"
        ;;
      succeeds)
        # shellcheck disable=SC2086
        $args >/dev/null 2>&1 || { echo "FAIL: command exited non-zero: $args"; exit 1; }
        echo "OK: $args"
        ;;
      best_effort)
        # shellcheck disable=SC2086
        $args 2>/dev/null | head -3 || true
        ;;
      *)
        echo "FAIL: unknown check type: $kind" >&2
        exit 1
        ;;
    esac
  done
' < "$CONTRACT"

echo
echo "Smoke test passed."
