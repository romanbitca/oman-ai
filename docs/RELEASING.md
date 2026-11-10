# Releasing OmanAI

GitHub Actions builds, signs, notarizes and publishes a release whenever a version tag is pushed. The setup below only has to be done once.

## One-time setup

You need a paid Apple Developer account and the [GitHub CLI](https://cli.github.com) signed in with write access to this repository. Never commit or paste any of the files or values from these steps.

### 1. Sign in to Xcode

Open Xcode, then Settings, then the Accounts tab. Press **+**, choose Apple ID and sign in with your Apple Developer account.

### 2. Create a Developer ID certificate

In the same tab, select your team and press **Manage Certificates**. Press **+**, choose **Developer ID Application** and press Done. Only the account holder can create this certificate.

If Xcode refuses with "This operation can only be performed by the Account Holder", create it on the website instead. In Keychain Access, click **login**, then use Certificate Assistant to save a certificate request to disk. On the [new certificate page](https://developer.apple.com/account/resources/certificates/add), choose **Developer ID Application**, select **G2 Sub-CA**, upload the request and download the certificate. Then install it:

```bash
security import ~/Downloads/developerID_application.cer -k ~/Library/Keychains/login.keychain-db
```

Check that it worked:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 3. Export the certificate

Open Keychain Access and go to the login keychain, then My Certificates. Right-click **Developer ID Application: your name**, choose Export and save it as a `.p12` file. Give it a strong password.

### 4. Create an App Store Connect API key

Go to [App Store Connect API keys](https://appstoreconnect.apple.com/access/integrations/api) and open Team Keys. Press **+**, name the key "OmanAI notarize" and choose **Developer** access. Download the `.p8` file, which you can only do once. Note the Key ID and the Issuer ID shown on that page.

### 5. Store everything

Run this in Terminal and answer the questions:

```bash
mac/scripts/setup-release-secrets.sh
```

It creates the key that signs updates, which stays in your login keychain, and stores these on GitHub without printing them:

| Name | Kind | What it is |
| --- | --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Secret | The exported certificate |
| `DEVELOPER_ID_P12_PASSWORD` | Secret | Its password |
| `NOTARY_KEY_BASE64` | Secret | The App Store Connect key |
| `NOTARY_KEY_ID` | Secret | Its Key ID |
| `NOTARY_ISSUER_ID` | Secret | Its Issuer ID |
| `SPARKLE_PRIVATE_KEY` | Secret | The key that signs updates |
| `SPARKLE_PUBLIC_KEY` | Variable | The public half, built into the app |

Afterwards, delete the `.p12` file and keep the `.p8` file somewhere safe.

The certificate has an expiry date, shown in Keychain Access. Apps you already released keep working after it, but new releases can't be signed until you create a new certificate and run the script again.

Back up the update key too. If it is lost, installed copies can no longer accept updates, and everyone would have to download a new version by hand. To export it, run `generate_keys -x <file>` from Sparkle's tools, and keep that file in a password manager.

## Publishing a release

Pick the next version number and push a tag from an up-to-date `main`:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The [Release workflow](../.github/workflows/release.yml) then:

1. Builds the app and signs it with Developer ID.
2. Notarizes it with Apple and staples the ticket.
3. Creates a GitHub release with generated notes, `OmanAI-0.2.0.zip` and `appcast.xml`.

The build number comes from the version, so `0.2.0` becomes `2000`. Version numbers must only ever go up.

## How updates reach people

The app checks `releases/latest/download/appcast.xml` once a day. A new version downloads in the background and installs when OmanAI quits. If it stays open for a week without quitting, it offers to install. The toggle is in Settings, under About.

A version installed before automatic updates existed has to be replaced by hand once.

macOS keeps the Accessibility permission across updates, because every release is signed by the same Developer ID team.

## Building a release on your own Mac

The setup script also saves your notary key for `release.sh`. From `mac/`:

```bash
SPARKLE_PUBLIC_KEY="$(build/packages/artifacts/sparkle/Sparkle/bin/generate_keys -p)" scripts/release.sh 0.2.0
```

The signed app ends up in `mac/build/release/export`.

## Forks

Set `APPLE_TEAM_ID` for your own team, and change `SUFeedURL` in `mac/project.yml` to your repository. Please also change the bundle ID, so your build doesn't collide with this one.
