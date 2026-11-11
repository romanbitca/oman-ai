# OmanAI

A macOS menu bar app that rewrites your text in your own voice.

Select text in any app, click the OmanAI icon and choose what you want. The result appears in a small panel under the menu bar, and one click puts it in place of your text. Nothing ever appears in or near the field you are typing in.

OmanAI is an early release, so expect rough edges. [KNOWN_ISSUES.md](KNOWN_ISSUES.md) lists the ones we know about.

## What it does

- **Proofread and Rewrite** selected text in any app.
- **Explain** tells you how a reader will understand what you wrote, and what they might misread.
- **Styles** built from messages you really wrote, so you can sound like yourself in Slack and like yourself in email.
- **Compose** new text from a short instruction.
- **Context** from the window you are writing in, pasted messages or the clipboard.
- **Your choice of model**: Claude Haiku, Sonnet or Opus with your own Anthropic API key, or Apple's on-device model for free.
- **Spending** per day and per week in Settings, estimated from what each Claude request used.
- **Shortcuts** for any action, and a panel you can pin and drag anywhere.

## Install

1. Download the latest `OmanAI-x.y.z.zip` from [Releases](https://github.com/romanbitca/oman-ai/releases).
2. Unzip it and move OmanAI to your Applications folder.
3. Open it, click its icon in the menu bar and follow the setup.

OmanAI needs macOS 14 or later. Apple's on-device model needs macOS 26 or later with Apple Intelligence turned on.

OmanAI updates itself from this repository's releases. You can turn that off in Settings, under About.

## Privacy

- Your styles and settings stay on your Mac in a local database, and your API key stays in the Keychain. For the spending charts, the database also keeps each Claude request's date, model and token counts, never its text.
- With Claude, each request sends the selected text, the chosen style's messages and any context you added to Anthropic, using your own API key.
- With Apple's on-device model, your writing stays on your Mac.
- The screen is included only when you turn that on, and the panel shows a preview of what will be sent.
- There are no analytics. Apart from your writing requests, OmanAI only contacts GitHub to check for updates.

macOS asks for two permissions. Accessibility lets OmanAI read your selection and paste the result. Screen Recording is only needed if you use the Screen option.

## Build from source

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen). No Apple Developer account is needed.

```bash
brew install xcodegen
cd mac
xcodegen generate
open Oman.xcodeproj
```

Run the tests with:

```bash
cd mac/OmanKit
swift test
```

Local builds are signed ad hoc and never update themselves. macOS treats each rebuild as a new app for its privacy permissions, so test Accessibility from a copy in `/Applications`.

## How the code is organised

- `mac/App` holds the menu bar item, the panel window and the updater.
- `mac/OmanKit` is a Swift package with all the logic: `OmanCore` (shared types), `ClaudeAPI` (Claude and Apple's model), `OmanStorage` (database and Keychain), `SystemBridge` (selection, paste, screen, shortcuts) and `OmanUI` (panel and Settings).
- `site` holds the landing page: one static HTML file with no build step and no outside requests.
- [PLAN.md](PLAN.md), [DECISIONS.md](DECISIONS.md) and [SESSION_LOG.md](SESSION_LOG.md) record the roadmap, the reasoning behind choices and the history of the work. [CLAUDE.md](CLAUDE.md) holds instructions for Claude Code.

An earlier Electron meeting recorder is kept on the [`archive/meeting-recorder`](https://github.com/romanbitca/oman-ai/tree/archive/meeting-recorder) branch.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Bundled libraries and their licenses are listed in [ThirdPartyNotices.txt](mac/App/ThirdPartyNotices.txt).
