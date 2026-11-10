#!/bin/bash
# Builds OmanAI, signs it with Developer ID, notarizes it, and leaves a stapled OmanAI.app in the output folder.
# Uses the Apple account signed in to Xcode. Usage: scripts/release.sh [output-folder]
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM=S72639F3BR
OUT="${1:-build/release}"
ARCHIVE="$OUT/OmanAI.xcarchive"

rm -rf "$OUT"
mkdir -p "$OUT"

xcodegen generate

xcodebuild archive \
    -project Oman.xcodeproj \
    -scheme Oman \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ENABLE_HARDENED_RUNTIME=YES \
    -allowProvisioningUpdates

# With destination "upload" this signs with Developer ID and submits the app to Apple's notary service.
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath "$OUT/submitted" \
    -allowProvisioningUpdates

for attempt in $(seq 1 40); do
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/notarized" >"$OUT/notary.log" 2>&1; then
        break
    fi
    if [ "$attempt" -eq 40 ]; then
        cat "$OUT/notary.log"
        echo "Apple did not finish notarizing in time." >&2
        exit 1
    fi
    sleep 30
done

APP="$OUT/notarized/OmanAI.app"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
echo "Ready: $APP"
