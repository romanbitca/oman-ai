# Claude Code Instructions

## Project context

OmanAI is a native macOS menu bar writing tool (Swift and SwiftUI), modelled on Apple's Writing Tools. It rewrites selected text or composes new text through the Anthropic API or Apple's on-device model, in styles built from the user's own messages. All UI opens from the menu bar icon; nothing appears in or near the text field being edited.

The earlier Electron meeting recorder is parked on the `archive/meeting-recorder` branch. See PLAN.md.

Always read PLAN.md, DECISIONS.md, KNOWN_ISSUES.md, and SESSION_LOG.md at the start of every session before writing code.

## Working agreement

- Implement only what the current task asks. No extra features.
- If a decision needs to be made that is not in DECISIONS.md, stop and ask the user.
- Update KNOWN_ISSUES.md when you discover bugs or workarounds.
- Update SESSION_LOG.md at the end of every session with what was done, dated.
- Never rewrite working code unless explicitly asked.
- After Swift changes, run `swift test` in `mac/OmanKit` and build the app (see Commands). Fix errors before declaring done.
- Commit at logical milestones with clear messages. Do not commit broken code.

## Commands

- Tests: `cd mac/OmanKit && swift test`
- Real answers from Claude, graded: `cd mac/OmanKit && OMAN_LIVE_KEY=<key> swift test --filter LiveWritingTests`. Run it after any change to a prompt. It costs about a cent on Haiku; the file's header lists the other settings
- Generate the Xcode project: `cd mac && xcodegen generate`
- Build the app: `cd mac && xcodebuild -project Oman.xcodeproj -scheme Oman -configuration Debug build`
- Publish a release: push a tag such as `v0.2.0`, and GitHub Actions does the rest. See docs/RELEASING.md
- Install on this Mac: `mac/scripts/release.sh <version>`, quit OmanAI, then `ditto mac/build/release/export/OmanAI.app /Applications/OmanAI.app`. Use only this build for the installed copy, because a different signature makes macOS ignore the Accessibility switch; see KNOWN_ISSUES.md

## Style

- Swift 6 language mode with strict concurrency
- No force unwraps or `fatalError` outside tests unless commented why
- Prefer explicit imports
- Comments only for non-obvious logic
- Swift file names, types and protocols: PascalCase
- Swift functions and variables: camelCase

## Stack constraints

- Swift and SwiftUI, with AppKit for the status item and panel
- XcodeGen for the app target; the `mac/OmanKit` Swift package holds all logic
- GRDB for SQLite, Keychain for the API key
- Sparkle for automatic updates, published through GitHub Releases
- Anthropic Messages API over URLSession, plus Apple's on-device model through FoundationModels; no other model provider
- Dictation on the Mac only: Apple's Speech framework (SpeechAnalyzer), Parakeet through FluidAudio and Whisper through WhisperKit; no speech service in the cloud
- macOS 14 or later

## Current phase

See PLAN.md - phase marked [IN PROGRESS]
