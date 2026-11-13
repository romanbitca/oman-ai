#!/bin/bash
# Makes OmanAI's disk image: the app beside a link to Applications, over a picture that says to drag one onto the
# other. It isn't signed here; release.sh signs and notarizes it.
# Usage: scripts/make-dmg.sh <OmanAI.app> <output.dmg>
#
# dmgbuild and the two packages it needs are installed into a throwaway folder, at the versions and hashes in
# dmg/requirements.txt. The picture's source is dmg/background.html, drawn at 660 by 400 points and twice that.
set -euo pipefail

APP_IN="${1:?Usage: scripts/make-dmg.sh <OmanAI.app> <output.dmg>}"
DMG_IN="${2:?Usage: scripts/make-dmg.sh <OmanAI.app> <output.dmg>}"
APP="$(cd "$(dirname "$APP_IN")" && pwd)/$(basename "$APP_IN")"
DMG="$(cd "$(dirname "$DMG_IN")" && pwd)/$(basename "$DMG_IN")"
if [ ! -d "$APP/Contents" ]; then
    echo "$APP_IN is not an app." >&2
    exit 1
fi

cd "$(dirname "$0")/.."
TOOLS="$(mktemp -d)"
trap 'rm -rf "$TOOLS"' EXIT
python3 -m venv "$TOOLS/venv"
"$TOOLS/venv/bin/pip" install --quiet --disable-pip-version-check \
    --require-hashes --no-deps --only-binary :all: -r dmg/requirements.txt

rm -f "$DMG"
# The volume is always called OmanAI, so the window finds its picture whatever the version.
"$TOOLS/venv/bin/dmgbuild" -s dmg/settings.py -D app="$APP" -D background="$PWD/dmg/background.png" \
    OmanAI "$DMG"
echo "Made $DMG"
