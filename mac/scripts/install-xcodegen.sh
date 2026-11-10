#!/bin/bash
# Downloads the one XcodeGen release this project is built with and checks its SHA-256, so the build
# tool can't change between releases without a change in this file.
# Prints the folder that holds the xcodegen binary.
# Usage: scripts/install-xcodegen.sh <folder>
#
# To move to a newer XcodeGen, change VERSION and take the new SHA256 from the "digest" of xcodegen.zip:
#   gh api repos/yonaskolb/XcodeGen/releases/tags/<version> --jq '.assets[] | "\(.name) \(.digest)"'
set -euo pipefail

VERSION="2.46.0"
SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"

DEST="${1:?Usage: scripts/install-xcodegen.sh <folder>}"
ZIP="$DEST/xcodegen-$VERSION.zip"

mkdir -p "$DEST"
curl --fail --silent --show-error --location --proto '=https' \
    --output "$ZIP" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"

if ! echo "$SHA256  $ZIP" | shasum -a 256 --check --status; then
    echo "XcodeGen $VERSION doesn't match the checksum in $(basename "$0"). Nothing was installed." >&2
    rm -f "$ZIP"
    exit 1
fi

unzip -q -o "$ZIP" -d "$DEST"
rm "$ZIP"
echo "$DEST/xcodegen/bin"
