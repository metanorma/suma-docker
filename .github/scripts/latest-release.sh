#!/usr/bin/env bash
# .github/scripts/latest-release.sh
#
# Fetch the latest stable X.Y.Z version from a remote source. Filters to
# strict semver and picks the highest. Outputs the version (e.g.
# "1.16.8") on stdout; exits non-zero on failure.
#
# Usage:
#   latest-release.sh dockerhub:<owner>/<image>
#   latest-release.sh github:<owner>/<repo>
#
# Examples:
#   latest-release.sh dockerhub:metanorma/metanorma
#   latest-release.sh github:expresslang/eengine-releases
#
# Used by the auto-sync workflows so the "what's the latest?" question
# has one answer per source, testable in isolation.
set -euo pipefail

SOURCE="${1:?Usage: $0 <dockerhub:owner/image | github:owner/repo>}"
KIND="${SOURCE%%:*}"
TARGET="${SOURCE#*:}"

case "$KIND" in
  dockerhub)
    # Docker Hub public tags API. No auth needed for public images.
    # Returns tags in order of last_pushed; we filter to strict semver
    # and pick the highest by sort -V.
    curl -fsSL "https://hub.docker.com/v2/repositories/${TARGET}/tags/?page_size=100" \
      | jq -r '.results[].name' \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
      | sort -V \
      | tail -1
    ;;
  github)
    # GitHub Releases API (uses gh CLI auth from GH_TOKEN env). Picks the
    # latest non-prerelease. Strips any non-numeric prefix from the tag
    # (handles "v1.2.3", "eeng-1.2.3", "release-1.2.3", etc.).
    TAG=$(gh api "repos/${TARGET}/releases/latest" --jq '.tag_name')
    printf '%s' "$TAG" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    ;;
  *)
    echo "Unknown source kind: $KIND (expected 'dockerhub' or 'github')" >&2
    exit 2
    ;;
esac
