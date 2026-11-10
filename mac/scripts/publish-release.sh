#!/bin/bash
# Publishes a build from release.sh as a GitHub release, together with the feed the app checks for updates.
# Usage: scripts/publish-release.sh <version> <release-folder>
#
# Needs SPARKLE_PRIVATE_KEY, and a gh login that can write to the repository.
set -euo pipefail

VERSION="${1:?Usage: scripts/publish-release.sh <version> <release-folder>}"
OUT="${2:?Usage: scripts/publish-release.sh <version> <release-folder>}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is not set}"

REPO="${GITHUB_REPOSITORY:-romanbitca/oman-ai}"
TAG="v$VERSION"
NAME="OmanAI-$VERSION"
FEED="$OUT/feed"
GENERATE_APPCAST="$OUT/derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"

rm -rf "$FEED"
mkdir -p "$FEED"
cp "$OUT/$NAME.zip" "$FEED/"

# A draft isn't "latest", so the app can't see the new feed until the zip is uploaded too.
gh release create "$TAG" --repo "$REPO" --verify-tag --draft --generate-notes --title "OmanAI $VERSION"
gh release view "$TAG" --repo "$REPO" --json body --jq .body >"$FEED/$NAME.md"

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
