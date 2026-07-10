#!/usr/bin/env bash
# Integration test: exercise suma's schema-generation pipeline against a
# real ISO 10303 collection without doing the slow document compilation.
#
# We use `suma generate-schemas` rather than `suma build` because:
#   - `suma build` has no flags to skip compilation (the README's
#     `--no-compile` doesn't exist in current suma).
#   - Full `suma build` of metanorma-smol.yml takes 30-60+ min (asciimath
#     rendering of 1008 formulas + many relaton network fetches).
#   - `suma generate-schemas` still exercises clone + suma CLI + eengine
#     + eep processing of EXPRESS schemas, which catches the failure
#     modes a smoke test misses.
#
# Usage: tests/integration.sh <image> [<repo-url>] [<ref>] [<manifest>]
#
# Defaults: clones metanorma/iso-10303@main and processes metanorma-smol.yml
# (the small test collection documented in this repo's README).
set -euo pipefail

IMAGE="${1:?Usage: $0 <image> [<repo-url>] [<ref>] [<manifest>]}"
REPO="${2:-https://github.com/metanorma/iso-10303.git}"
REF="${3:-main}"
MANIFEST="${4:-metanorma-smol.yml}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Integration test:"
echo "  image:     ${IMAGE}"
echo "  repo:      ${REPO}"
echo "  ref:       ${REF}"
echo "  manifest:  ${MANIFEST}"
echo

echo "Cloning ${REPO} (ref=${REF}, shallow)..."
# Use gh if available (respects GH_TOKEN for private repos in CI); fall
# back to plain git clone for public repos / local runs without gh.
if command -v gh >/dev/null 2>&1; then
  REPO_NO_GIT="${REPO%.git}"
  REPO_NO_GIT="${REPO_NO_GIT#https://github.com/}"
  gh repo clone "${REPO_NO_GIT}" "${WORKDIR}/repo" -- --depth=1 --branch "${REF}"
else
  git clone --depth=1 --branch "${REF}" "${REPO}" "${WORKDIR}/repo"
fi

echo
echo "Running: docker run ... suma generate-schemas ${MANIFEST} /tmp/schemas-out.yml"
docker run --rm -v "${WORKDIR}/repo:/metanorma" "${IMAGE}" \
  suma generate-schemas "${MANIFEST}" /metanorma/schemas-out.yml

echo
echo "Verifying output..."
test -f "${WORKDIR}/repo/schemas-out.yml"
echo "  OK: schemas-out.yml exists"

SCHEMA_ENTRIES=$(grep -c '^-' "${WORKDIR}/repo/schemas-out.yml" 2>/dev/null || echo 0)
if [ "${SCHEMA_ENTRIES}" -lt 1 ]; then
  echo "  FAIL: schemas-out.yml has no schema entries"
  exit 1
fi
echo "  OK: ${SCHEMA_ENTRIES} schema entries found in schemas-out.yml"

echo
echo "Integration test passed."
