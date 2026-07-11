#!/usr/bin/env bash
# .github/scripts/image-metadata.sh
#
# Single source of truth for image metadata extracted from this repo's
# VERSION and Dockerfile(s). Outputs KEY=VALUE lines on stdout — suitable
# for appending to $GITHUB_OUTPUT in a workflow step, or `eval` into shell
# variables for local use.
#
# Keys emitted:
#   version              — contents of VERSION file (X.Y.Z[.N])
#   major                — first component
#   minor                — second component
#   patch                — third component
#   major_minor          — e.g. "1.16"
#   major_minor_patch    — e.g. "1.16.8" (trims any .N suffix)
#   linux_base_image     — full FROM image from Dockerfile (e.g. metanorma/metanorma:1.16.8)
#   linux_base_version   — just the version part (e.g. 1.16.8)
#   eengine_version      — ARG EENGINE_VERSION from Dockerfile (e.g. 5.2.7)
#   windows_base_image   — ARG BASE_IMAGE from Dockerfile.windows
#
# Usage in a GitHub Actions step:
#   - id: meta
#     run: .github/scripts/image-metadata.sh >> "$GITHUB_OUTPUT"
#
# Usage locally:
#   eval "$(./.github/scripts/image-metadata.sh)"
set -euo pipefail

# Resolve repo root regardless of cwd.
cd "$(dirname "$0")/../.."

VERSION=$(cat VERSION 2>/dev/null || echo "0.0.0")

MAJOR=$(printf '%s' "$VERSION" | cut -d. -f1)
MINOR=$(printf '%s' "$VERSION" | cut -d. -f2)
PATCH=$(printf '%s' "$VERSION" | cut -d. -f3)
MAJOR_MINOR="${MAJOR}.${MINOR}"
MAJOR_MINOR_PATCH="${MAJOR}.${MINOR}.${PATCH}"

LINUX_BASE_IMAGE=$(grep -E '^FROM ' Dockerfile | head -1 | awk '{print $2}')
LINUX_BASE_VERSION=${LINUX_BASE_IMAGE##*:}

EENGINE_VERSION=$(grep -E '^ARG EENGINE_VERSION' Dockerfile | head -1 | awk -F'=' '{print $2}')

WINDOWS_BASE_IMAGE=$(grep -E '^ARG BASE_IMAGE' Dockerfile.windows | head -1 | awk -F'=' '{print $2}')

{
  echo "version=${VERSION}"
  echo "major=${MAJOR}"
  echo "minor=${MINOR}"
  echo "patch=${PATCH}"
  echo "major_minor=${MAJOR_MINOR}"
  echo "major_minor_patch=${MAJOR_MINOR_PATCH}"
  echo "linux_base_image=${LINUX_BASE_IMAGE}"
  echo "linux_base_version=${LINUX_BASE_VERSION}"
  echo "eengine_version=${EENGINE_VERSION}"
  echo "windows_base_image=${WINDOWS_BASE_IMAGE}"
}
