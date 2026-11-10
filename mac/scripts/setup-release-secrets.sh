#!/bin/bash
# One-time maintainer setup. Creates the key that signs updates, and stores the release secrets on GitHub
# in a protected environment: a release can read them only after you approve it, and only from a version tag.
# Run it yourself in Terminal, because it asks for a password. It never prints a secret.
# docs/RELEASING.md explains how to get the two files it asks for.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="${GITHUB_REPOSITORY:-romanbitca/oman-ai}"
ENVIRONMENT="release"
PACKAGES="build/packages"
SECRETS=(
    SPARKLE_PRIVATE_KEY
    DEVELOPER_ID_P12_BASE64
    DEVELOPER_ID_P12_PASSWORD
    NOTARY_KEY_BASE64
    NOTARY_KEY_ID
    NOTARY_ISSUER_ID
)

# Paths dragged into Terminal arrive with backslashes or quotes, and a trailing space.
clean_path() {
    local path="${1%% }"
    path="${path//\\/}"
    path="${path#\'}"
    path="${path%\'}"
    printf %s "${path/#\~/$HOME}"
}

IDENTITIES="$(security find-identity -v -p codesigning)"
if ! grep -q "Developer ID Application" <<<"$IDENTITIES"; then
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
for file in "$P12_PATH" "$NOTARY_KEY_PATH"; do
    if [ ! -f "$file" ]; then
        echo "Can't find $file" >&2
        exit 1
    fi
done
# The password reaches openssl on its input, so it never shows in the list of running programs.
if ! openssl pkcs12 -in "$P12_PATH" -nokeys -passin stdin >/dev/null 2>&1 <<<"$P12_PASSWORD" &&
    ! openssl pkcs12 -legacy -in "$P12_PATH" -nokeys -passin stdin >/dev/null 2>&1 <<<"$P12_PASSWORD"; then
    echo "That password doesn't open the .p12 file." >&2
    exit 1
fi

xcodegen generate >/dev/null
xcodebuild -resolvePackageDependencies -project Oman.xcodeproj -scheme Oman -clonedSourcePackagesDirPath "$PACKAGES" >/dev/null
SPARKLE_BIN="$PACKAGES/artifacts/sparkle/Sparkle/bin"

# Creates the key in your login keychain the first time, and reuses it afterwards.
"$SPARKLE_BIN/generate_keys" >/dev/null
SPARKLE_PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"

KEY_FOLDER="$(mktemp -d)"
trap 'rm -rf "$KEY_FOLDER"' EXIT
"$SPARKLE_BIN/generate_keys" -x "$KEY_FOLDER/sparkle.key" >/dev/null

# The environment asks you to approve every job that wants its secrets, and only lets version tags in.
REVIEWER_ID="$(gh api user --jq .id)"
gh api --method PUT "repos/$REPO/environments/$ENVIRONMENT" --input - >/dev/null <<EOF
{
  "reviewers": [{ "type": "User", "id": $REVIEWER_ID }],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
EOF
POLICIES="$(gh api "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" --jq '.branch_policies[].name')"
if ! grep -qxF 'v*' <<<"$POLICIES"; then
    gh api --method POST "repos/$REPO/environments/$ENVIRONMENT/deployment-branch-policies" \
        -f name='v*' -f type=tag >/dev/null
fi

gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" --env "$ENVIRONMENT" <"$KEY_FOLDER/sparkle.key"
base64 -i "$P12_PATH" | gh secret set DEVELOPER_ID_P12_BASE64 --repo "$REPO" --env "$ENVIRONMENT"
printf %s "$P12_PASSWORD" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$REPO" --env "$ENVIRONMENT"
base64 -i "$NOTARY_KEY_PATH" | gh secret set NOTARY_KEY_BASE64 --repo "$REPO" --env "$ENVIRONMENT"
printf %s "$NOTARY_KEY_ID" | gh secret set NOTARY_KEY_ID --repo "$REPO" --env "$ENVIRONMENT"
printf %s "$NOTARY_ISSUER_ID" | gh secret set NOTARY_ISSUER_ID --repo "$REPO" --env "$ENVIRONMENT"
gh variable set SPARKLE_PUBLIC_KEY --repo "$REPO" --body "$SPARKLE_PUBLIC_KEY"

# Copies left on the repository itself could be read by a workflow on any branch, so they go.
for name in "${SECRETS[@]}"; do
    gh secret delete "$name" --repo "$REPO" >/dev/null 2>&1 || true
done

# Lets scripts/release.sh notarize from this Mac too.
xcrun notarytool store-credentials OmanAI \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >/dev/null

echo "All set. The secrets are in the \"$ENVIRONMENT\" environment, and releases wait for your approval on GitHub."
echo "You can delete the .p12 file now. Keep the .p8 file somewhere safe."
