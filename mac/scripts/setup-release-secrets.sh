#!/bin/bash
# One-time maintainer setup. Creates the key that signs updates and stores the release secrets on GitHub.
# Run it yourself in Terminal, because it asks for a password. It never prints a secret.
# docs/RELEASING.md explains how to get the two files it asks for.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="${GITHUB_REPOSITORY:-romanbitca/oman-ai}"
PACKAGES="build/packages"

# Paths dragged into Terminal arrive with backslashes and a trailing space.
clean_path() {
    local path="${1%% }"
    path="${path//\\/}"
    printf %s "${path/#\~/$HOME}"
}

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "There is no Developer ID Application certificate in your keychain. See docs/RELEASING.md." >&2
    exit 1
fi

read -r -p "Drag in the exported .p12 file, then press Return: " P12_PATH
read -r -s -p "Password you gave the .p12 file: " P12_PASSWORD
echo
read -r -p "Drag in the App Store Connect .p8 file, then press Return: " NOTARY_KEY_PATH
read -r -p "App Store Connect Key ID: " NOTARY_KEY_ID
read -r -p "App Store Connect Issuer ID: " NOTARY_ISSUER_ID
P12_PATH="$(clean_path "$P12_PATH")"
NOTARY_KEY_PATH="$(clean_path "$NOTARY_KEY_PATH")"

xcodegen generate >/dev/null
xcodebuild -resolvePackageDependencies -project Oman.xcodeproj -scheme Oman -clonedSourcePackagesDirPath "$PACKAGES" >/dev/null
SPARKLE_BIN="$PACKAGES/artifacts/sparkle/Sparkle/bin"

# Creates the key in your login keychain the first time, and reuses it afterwards.
"$SPARKLE_BIN/generate_keys" >/dev/null
SPARKLE_PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"

KEY_FOLDER="$(mktemp -d)"
trap 'rm -rf "$KEY_FOLDER"' EXIT
"$SPARKLE_BIN/generate_keys" -x "$KEY_FOLDER/sparkle.key" >/dev/null

gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" <"$KEY_FOLDER/sparkle.key"
base64 -i "$P12_PATH" | gh secret set DEVELOPER_ID_P12_BASE64 --repo "$REPO"
printf %s "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPO"
base64 -i "$NOTARY_KEY_PATH" | gh secret set NOTARY_KEY_BASE64 --repo "$REPO"
printf %s "$NOTARY_KEY_ID" | gh secret set NOTARY_KEY_ID --repo "$REPO"
printf %s "$NOTARY_ISSUER_ID" | gh secret set NOTARY_ISSUER_ID --repo "$REPO"
gh variable set SPARKLE_PUBLIC_KEY --repo "$REPO" --body "$SPARKLE_PUBLIC_KEY"

# Lets scripts/release.sh notarize from this Mac too.
xcrun notarytool store-credentials OmanAI \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >/dev/null

echo "All set. You can delete the .p12 file now. Keep the .p8 file somewhere safe."
