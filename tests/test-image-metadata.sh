#!/usr/bin/env bash
# Sanity check for .github/scripts/image-metadata.sh.
#
# Verifies the script produces all expected keys and that the values
# match the formats the rest of CI relies on (version is X.Y.Z[.N],
# major_minor_patch is the first three components, etc.).
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT=$(./.github/scripts/image-metadata.sh)

get() {
    printf '%s\n' "$OUTPUT" | grep "^$1=" | cut -d= -f2-
}

# All keys must be present and non-empty.
for key in version major minor patch major_minor major_minor_patch \
           linux_base_image linux_base_version eengine_version windows_base_image; do
    val=$(get "$key")
    if [ -z "$val" ]; then
        echo "FAIL: missing or empty key: $key"
        exit 1
    fi
done

# version must be X.Y.Z or X.Y.Z.N
VERSION=$(get version)
if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    echo "FAIL: version '$VERSION' is not X.Y.Z[.N]"
    exit 1
fi

# major_minor_patch must equal the first three components of version
EXPECTED_MMP=$(printf '%s' "$VERSION" | cut -d. -f1-3)
ACTUAL_MMP=$(get major_minor_patch)
if [ "$EXPECTED_MMP" != "$ACTUAL_MMP" ]; then
    echo "FAIL: major_minor_patch='$ACTUAL_MMP' expected '$EXPECTED_MMP'"
    exit 1
fi

# linux_base_image must look like an image:tag
LINUX_BASE=$(get linux_base_image)
if ! printf '%s' "$LINUX_BASE" | grep -q ':'; then
    echo "FAIL: linux_base_image '$LINUX_BASE' has no :tag separator"
    exit 1
fi

# linux_base_version must equal the part after the last colon
ACTUAL_LBV=$(get linux_base_version)
EXPECTED_LBV=${LINUX_BASE##*:}
if [ "$ACTUAL_LBV" != "$EXPECTED_LBV" ]; then
    echo "FAIL: linux_base_version='$ACTUAL_LBV' expected '$EXPECTED_LBV'"
    exit 1
fi

# eengine_version must be three-part numeric
EE=$(get eengine_version)
if ! printf '%s' "$EE" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "FAIL: eengine_version '$EE' is not X.Y.Z"
    exit 1
fi

echo "PASS: image-metadata.sh produces expected output"
echo "  version=$VERSION"
echo "  linux_base_image=$LINUX_BASE"
echo "  eengine_version=$EE"
