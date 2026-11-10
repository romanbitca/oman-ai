# Claude Code Instructions

## Project context

oman is a native macOS menu bar writing tool (Swift and SwiftUI), modelled on Apple's Writing Tools. It rewrites selected text or composes new text through the Anthropic API, in styles built from the user's own messages. All UI opens from the menu bar icon; nothing appears in or near the text field being edited.

The earlier Electron meeting recorder (`electron/`, `src/`, `shared/`) is parked. See PLAN.md.

Always read PLAN.md, DECISIONS.md, KNOWN_ISSUES.md, and SESSION_LOG.md at the start of every session before writing code.

## Working agreement

- Implement only what the current task asks. No extra features.
- If a decision needs to be made that is not in DECISIONS.md, stop and ask the user.
- Update KNOWN_ISSUES.md when you discover bugs or workarounds.
- Update SESSION_LOG.md at the end of every session with what was done, dated.
- Never rewrite working code unless explicitly asked.
- After Swift changes, run `swift test` in `mac/OmanKit` and build the app (see Commands). Fix errors before declaring done.
- After changes to the parked Electron code, run `npm run typecheck` and `npm run lint`.
- Commit at logical milestones with clear messages. Do not commit broken code.

## Commands

- Tests: `cd mac/OmanKit && swift test`
- Generate the Xcode project: `cd mac && xcodegen generate`
- Build the app: `cd mac && xcodebuild -project Oman.xcodeproj -scheme Oman -configuration Debug build`
- Install for real use: build with `-configuration Release`, quit oman, then `ditto <built oman.app> /Applications/oman.app`. Privacy permissions need an installed copy; see KNOWN_ISSUES.md

## Style

- Swift 6 language mode with strict concurrency
- No force unwraps or `fatalError` outside tests unless commented why
- Prefer explicit imports
- Comments only for non-obvious logic
- Swift file names, types and protocols: PascalCase
- Swift functions and variables: camelCase
- The parked TypeScript code keeps its rules: strict mode, no `any` unless commented why, kebab-case file names

## Stack constraints

- Swift and SwiftUI, with AppKit for the status item and panel
- XcodeGen for the app target; the `mac/OmanKit` Swift package holds all logic
- GRDB for SQLite, Keychain for the API key
- Anthropic Messages API over URLSession; no other model provider
- macOS 14 or later

## Current phase

See PLAN.md - phase marked [IN PROGRESS]
