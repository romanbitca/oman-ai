#!/bin/bash
# Builds OmanAI, signs it with Developer ID, notarizes it and writes a stapled zip to the output folder.
# Usage: scripts/release.sh <version> [output-folder]
#
# Needs a "Developer ID Application" certificate in the keychain, and one of these for notarizing:
#   NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID, for an App Store Connect API key
#   a notarytool keychain profile, named by NOTARY_PROFILE (default OmanAI)
# SPARKLE_PUBLIC_KEY turns on automatic updates in the build. See docs/RELEASING.md.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:?Usage: scripts/release.sh <version> [output-folder]}"
OUT="${2:-build/release}"
TEAM="${APPLE_TEAM_ID:-S72639F3BR}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "The version must look like 1.2.3" >&2
    exit 1
fi
IFS=. read -r MAJOR MINOR PATCH <<<"$VERSION"
# Sparkle compares this number, so it has to grow with every release.
BUILD=$((10#$MAJOR * 1000000 + 10#$MINOR * 1000 + 10#$PATCH))

if [ -n "${NOTARY_KEY_PATH:-}" ]; then
    NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER_ID:?}")
else
    NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE:-OmanAI}")
fi

ARCHIVE="$OUT/OmanAI.xcarchive"
APP="$OUT/export/OmanAI.app"
ZIP="$OUT/OmanAI-$VERSION.zip"

rm -rf "$OUT"
mkdir -p "$OUT"

xcodegen generate

xcodebuild archive \
    -project Oman.xcodeproj \
    -scheme Oman \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$OUT/derived" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ENABLE_HARDENED_RUNTIME=YES \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"

cp ExportOptions.plist "$OUT/ExportOptions.plist"
plutil -replace teamID -string "$TEAM" "$OUT/ExportOptions.plist"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/export"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" "${NOTARY_AUTH[@]}" --wait --timeout 30m
rm "$OUT/notarize.zip"

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# The zip has to come after stapling, so the ticket travels with the app.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "Ready: $ZIP"
