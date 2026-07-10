#!/usr/bin/env bash
# Integration test: build a real ISO 10303 collection with `suma build`
# inside the image and verify output. This is the test that catches
# "the image starts but suma can't actually build anything" failures
# that a pure smoke test misses.
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

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Integration test:"
echo "  image:     ${IMAGE}"
echo "  repo:      ${REPO}"
echo "  ref:       ${REF}"
echo "  manifest:  ${MANIFEST}"
echo

echo "Cloning ${REPO} (ref=${REF}, shallow)..."
git clone --depth=1 --branch "${REF}" "${REPO}" "${WORKDIR}/repo"

echo
echo "Running: docker run ... suma build ${MANIFEST}"
docker run --rm -v "${WORKDIR}/repo:/metanorma" "${IMAGE}" \
  suma build "${MANIFEST}"

echo
echo "Verifying output..."
test -f "${WORKDIR}/repo/_site/index.html"
echo "  OK: _site/index.html exists"

HTML_FILES=$(find "${WORKDIR}/repo/_site" -name '*.html' | wc -l | tr -d ' ')
if [ "${HTML_FILES}" -lt 1 ]; then
  echo "  FAIL: no HTML files generated"
  exit 1
fi
echo "  OK: ${HTML_FILES} HTML file(s) generated"

echo
echo "Integration test passed."
