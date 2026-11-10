#!/bin/bash
# Publishes a build from release.sh as a GitHub release, together with the feed the app checks for updates.
# Usage: scripts/publish-release.sh <version> <release-folder>
#
# Needs SPARKLE_PRIVATE_KEY, XcodeGen, and a gh login that can write to the repository.
set -euo pipefail

VERSION="${1:?Usage: scripts/publish-release.sh <version> <release-folder>}"
OUT="${2:?Usage: scripts/publish-release.sh <version> <release-folder>}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is not set}"

REPO="${GITHUB_REPOSITORY:-romanbitca/oman-ai}"
TAG="v$VERSION"
NAME="OmanAI-$VERSION"

if [ ! -f "$OUT/$NAME.zip" ]; then
    echo "Can't find $OUT/$NAME.zip. Build it with scripts/release.sh first." >&2
    exit 1
fi
OUT="$(cd "$OUT" && pwd)"
FEED="$OUT/feed"
PACKAGES="$OUT/packages"

# Sparkle's tools are fetched here, at the version the project pins, and not taken from the folder
# the app was built in. Anything that ran during the build has had no chance to change them.
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -resolvePackageDependencies -project Oman.xcodeproj -scheme Oman \
    -clonedSourcePackagesDirPath "$PACKAGES" >/dev/null
GENERATE_APPCAST="$PACKAGES/artifacts/sparkle/Sparkle/bin/generate_appcast"

rm -rf "$FEED"
mkdir -p "$FEED"
cp "$OUT/$NAME.zip" "$FEED/"

# A draft isn't "latest", so the app can't see the new feed until the zip is uploaded too.
gh release create "$TAG" --repo "$REPO" --verify-tag --draft --generate-notes --title "OmanAI $VERSION"
gh release view "$TAG" --repo "$REPO" --json body --jq .body >"$FEED/$NAME.md"

# The app asks for a signed feed (SURequireSignedFeed), so generate_appcast signs the feed and the
# release notes as well as the zip.
printf %s "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" \
    --ed-key-file - \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --embed-release-notes \
    --full-release-notes-url "https://github.com/$REPO/releases" \
    -o "$FEED/appcast.xml" \
    "$FEED"

gh release upload "$TAG" --repo "$REPO" "$FEED/$NAME.zip" "$FEED/appcast.xml"
gh release edit "$TAG" --repo "$REPO" --draft=false --latest
echo "Published $TAG"
