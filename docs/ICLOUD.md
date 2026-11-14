# Syncing through iCloud

OmanAI can keep your styles, actions and writing settings the same on your Mac and your iPhone, through your own iCloud. It is off until you turn on **Sync with iCloud**: in Settings, General on the Mac, and in Settings on the iPhone. Each device has its own switch.

## What syncs

- Your styles, with their notes and the messages they are built from.
- Your actions.
- These settings: Quality, the language to answer in, your instructions, the default style, whether each app remembers its style, how Proofread shows its changes, your dictation words, and whether filler words are taken out.

What stays on each device: your API key, in that device's Keychain; your transcripts and counts; the dictation models and the model chosen; the writing model; the theme, the panel's settings, shortcuts, the microphone and sounds; and the style last chosen in each app.

## How it works

Everything goes to a zone of OmanAI's own in the private database of your iCloud, which only your Apple Account can reach. The names, notes, messages, instructions and settings are in CloudKit's encrypted fields: your device encrypts them with keys kept in your iCloud Keychain, so Apple can't read them. Only the dates of changes are stored plainly.

When the same thing changed on two devices, the newer change wins. A style or an action is taken whole. Settings are weighed one at a time, so a change to one setting on the iPhone doesn't undo a change to another on the Mac. When syncing is first turned on, a setting you changed before beats one still at its default, so a new iPhone takes on the Mac's settings rather than the other way round.

A deletion on one device deletes on the others, unless the other device changed that style or action since; then the change brings it back. Changes are sent a few moments after they are saved, and fetched when OmanAI starts, when it comes to the front, and every five minutes while it runs.

Turning the switch off leaves what is in iCloud there, and leaves everything on the device. If you delete OmanAI's data from iCloud in your Apple Account's settings, each device stops syncing when it notices, rather than sending it all back.

## Builds that can sync

CloudKit stops an app that asks for a container it isn't entitled to. So OmanAI only reaches iCloud in a build signed for its container, `iCloud.com.romanbitca.oman`, whose Info.plist names it under `OmanICloudContainer`. Every other build, the ones made with `xcodebuild` in the README among them, has no switch and never touches CloudKit. Syncing needs a paid Apple Developer account.

### The iPhone app from Xcode

1. Set up `mac/Signing.xcconfig` as [IPHONE.md](IPHONE.md) says, with your paid team.
2. In it, take away the two slashes in front of the `OMAN_ICLOUD_CONTAINER` and `CODE_SIGN_ENTITLEMENTS` lines, and run `xcodegen generate` in `mac`.
3. Open the OmanMobile target's Signing & Capabilities in Xcode. iCloud shows with CloudKit and the container. If Xcode says the container doesn't exist, press **+** under Containers and add `iCloud.com.romanbitca.oman` once for the team.
4. Run it on the iPhone, which has to be signed in to iCloud.

Builds run from Xcode use CloudKit's development environment. Its first syncs create the record types Style, Action and Settings.

### The Mac app, signed with Developer ID

A Developer ID app needs a provisioning profile for iCloud. `scripts/release.sh` doesn't make one or use one yet.

1. On [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list), open the identifier `com.romanbitca.oman`, turn on iCloud with CloudKit, and choose the container.
2. Under Profiles, press **+**, choose **Developer ID**, then that identifier, and download the profile. Double-click it to install it.
3. Build with these settings added to the `xcodebuild archive` command in `scripts/release.sh`, with the profile's name:

   ```bash
   OMAN_ICLOUD_CONTAINER=iCloud.com.romanbitca.oman \
   CODE_SIGN_ENTITLEMENTS=App/OmanCloud.entitlements \
   PROVISIONING_PROFILE_SPECIFIER="the profile's name"
   ```

   `ExportOptions.plist` then needs the profile under `provisioningProfiles`, and GitHub Actions needs the profile as a secret, as it has the certificate.

Release builds use CloudKit's production environment. Before the first one can sync, open the container in [CloudKit Console](https://icloud.developer.apple.com), go to Schema and press **Deploy Schema Changes**, so that production has the record types the development builds made.

Development and production keep separate data. For a Mac release and an iPhone built from Xcode to see each other's changes, add `com.apple.developer.icloud-container-environment` with the value `Production` to `mac/iOS/OmanMobileCloud.entitlements`.
