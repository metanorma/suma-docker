#!/usr/bin/env bash
# Integration test: build a real ISO 10303 collection with `suma build`
# inside the image and verify output. This is the test that catches
# "the image starts but suma can't actually build anything" failures
# that a pure smoke test misses.
#
# Uses --no-compile by default: exercises collection parsing, manifest
# generation, schema adoc generation (via eengine/eep), but skips the
# slow document compilation (asciimath, relaton fetches, etc.) that
# pushes the full smol build past 30+ minutes. Set SUMA_BUILD_ARGS to
# override (e.g. SUMA_BUILD_ARGS="" for a full build).
#
# Usage: tests/integration.sh <image> [<repo-url>] [<ref>] [<manifest>]
#
# Defaults: clones metanorma/iso-10303@main and builds metanorma-smol.yml
# (the small test collection documented in this repo's README).
set -euo pipefail

IMAGE="${1:?Usage: $0 <image> [<repo-url>] [<ref>] [<manifest>]}"
REPO="${2:-https://github.com/metanorma/iso-10303.git}"
REF="${3:-main}"
MANIFEST="${4:-metanorma-smol.yml}"
SUMA_BUILD_ARGS="${SUMA_BUILD_ARGS:---no-compile}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Integration test:"
echo "  image:         ${IMAGE}"
echo "  repo:          ${REPO}"
echo "  ref:           ${REF}"
echo "  manifest:      ${MANIFEST}"
echo "  suma build args: ${SUMA_BUILD_ARGS:-<none>}"
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
echo "Running: docker run ... suma build ${SUMA_BUILD_ARGS} ${MANIFEST}"
# shellcheck disable=SC2086
docker run --rm -v "${WORKDIR}/repo:/metanorma" "${IMAGE}" \
  suma build ${SUMA_BUILD_ARGS} "${MANIFEST}"

echo
echo "Verifying output..."
# --no-compile produces schema_docs/ but may not produce _site/.
# Require at least one of them as evidence the build actually ran.
if [ -d "${WORKDIR}/repo/_site" ]; then
  HTML_FILES=$(find "${WORKDIR}/repo/_site" -name '*.html' | wc -l | tr -d ' ')
  echo "  OK: _site/ exists (${HTML_FILES} HTML files)"
elif [ -d "${WORKDIR}/repo/schema_docs" ]; then
  SCHEMA_DOCS=$(find "${WORKDIR}/repo/schema_docs" -name '*.adoc' | wc -l | tr -d ' ')
  echo "  OK: schema_docs/ exists (${SCHEMA_DOCS} generated adoc files)"
else
  echo "  FAIL: neither _site/ nor schema_docs/ was produced"
  exit 1
fi

echo
echo "Integration test passed."
