# OmanAI on the iPhone

The iPhone app does what the Mac app does, in four tabs:

- **Write.** Paste, type or dictate a text, then Proofread, Rewrite, Explain, Compose or run one of your actions, with your styles and context. **Use** puts the result back in the box; **Copy** takes it to another app.
- **Dictate.** Tap the microphone and talk. Your words show as you say them and are copied when you finish, to paste anywhere. **Proofread** and **Rewrite** take them straight to Write.
- **Home.** What you wrote and dictated, counted, and your transcripts, as in OmanAI's window on the Mac.
- **Settings.** The model and your API key, how Proofread shows its changes, styles, actions, dictation and iCloud.

It needs iOS 26 or later. Claude needs your Anthropic API key, saved in the iPhone's Keychain. Apple's on-device model needs Apple Intelligence switched on, which needs an iPhone 15 Pro or later. Every dictation model runs on the phone.

What only the Mac has: the menu bar, shortcuts, the pill, reading the text selected in another app and writing over it, the picture of the screen, and Accessibility. iOS lets no app read or change another app's text, so on the iPhone you bring text to OmanAI and take the result back with Copy.

## Run it in the simulator

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd mac && xcodegen generate
```

Open `mac/Oman.xcodeproj`, choose the **OmanMobile** scheme and an iPhone simulator, and press Run. The simulator needs no signing.

## Run it on your iPhone

1. Copy `mac/Signing.example.xcconfig` to `mac/Signing.xcconfig`. Git ignores the copy.
2. Put your team's ID in it. It is under Membership details on [developer.apple.com](https://developer.apple.com/account). A free Apple Account works too: sign in to it in Xcode's Settings, Accounts, and use the ID Xcode shows for your Personal Team.
3. Run `xcodegen generate` again in `mac`.
4. Connect the iPhone, choose it and the **OmanMobile** scheme in Xcode, and press Run.

The first time, the iPhone asks you to turn on Developer Mode, in Settings, Privacy & Security. With a free account, it also asks you to trust your certificate, in Settings, General, VPN & Device Management, and the app stops opening after seven days until you run it from Xcode again.

To sync with your Mac through iCloud, see [ICLOUD.md](ICLOUD.md).
