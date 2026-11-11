# Decisions

Append-only log of architectural choices. Never delete entries; supersede with new ones if needed.

---

## 2026-04-28 — Stack

- Electron over Tauri: Claude Code is stronger in JS/TS than Rust
- better-sqlite3 over Prisma or Drizzle: lightweight, sync API, fits Electron main process
- Whisper.cpp for local transcription, Deepgram for cloud option (later phase)
- Native Swift binary for Mac audio (ScreenCaptureKit), called via child_process
- Native C# binary for Windows audio (later phase, P11)
- React 18 + Tailwind + shadcn/ui for renderer
- Zustand for renderer state, IPC for renderer-to-main

## 2026-04-28 — Scope of v1

- Manual record button AND auto-detect, both supported
- No real-time transcription; post-meeting only
- No AI summary in v1; just transcript
- Multi-workspace; one SQLite file per workspace
- Google OAuth scopes limited to Calendar (read) and Drive (write)
- Audio stored locally; transcripts also pushed to Drive on user action
- Transcript can be pasted into Claude project chat or read via Google Drive MCP
- App name: oman
- Distribution: direct download from GitHub releases
- No encryption at rest in v1

## 2026-04-28 — Anti-decisions (explicitly out of scope for v1)

- No SOC 2, HIPAA, or audit logs
- No mobile companion app
- No team sharing or collaboration
- No web app
- No Linux build
- No real-time transcript
- No AI summary or chat with meeting

## 2026-04-28 — P1 implementation decisions

- `sandbox: false` in renderer webPreferences: preload is emitted as ESM (`.mjs`) and Electron 33's sandbox does not load ESM preloads (combo fails silently). `contextIsolation: true` and `nodeIntegration: false` remain on. Revisit during P12 hardening; tracked in KNOWN_ISSUES.md
- App ID `com.romanbitca.oman`: required by electron-builder; uses owner.appname reverse-DNS convention
- Mac `identity: null` in electron-builder.yml: skip code signing so unsigned local `dist:mac` builds work without a paid Apple Developer cert. P12 will wire real signing
- Tailwind v3 (not v4) and ESLint v8 with classic `.eslintrc.cjs` (not flat config): well-tested pairing with shadcn/ui CLI today; migrate when shadcn templates default to v4/v9
- Tray icon is a macOS template image (`image.setTemplateImage(true)` on darwin): black + alpha PNG auto-inverts to match the menu bar in dark/light mode
- App keeps running when the main window is closed (empty `window-all-closed` handler): the tray is the persistent UI; quitting only happens via tray menu or Cmd+Q
- External links from the renderer open in the system browser (`shell.openExternal` from a `setWindowOpenHandler` that returns `{ action: 'deny' }`): keeps the Electron window scoped to the app's own UI

## 2026-04-28 — P2 implementation decisions

- Workspace dir = `app.getPath('userData') + '/workspaces'`: Electron's `userData` already maps to `~/Library/Application Support/oman` on Mac and `%APPDATA%/oman` on Windows (driven by `package.json` `name`), so this matches the spec paths without hardcoding per-OS branches
- Migration strategy = `PRAGMA user_version` + an array of `(db) => void` callbacks, each step wrapped in a transaction. No `_migrations` table. Bumps are append-only — never edit a past entry, add a new one
- Workspace display name = the slug itself: schema has no separate workspace-name field and the spec doesn't ask for one. UI shows `personal`, `work-test`, etc. User-entered names are slugified (lowercase, alnum, dash-separated) before save
- `createWorkspace` auto-switches in the IPC handler: creating from the dropdown is a "make and use" action; a non-switching create would be a dead branch in v1
- Active workspace is **not** persisted across launches: every launch opens the oldest-by-creation workspace (i.e. `personal` unless deleted). Spec only mandates auto-create on first launch; persistence can be added later if it becomes friction
- WAL journal mode (`PRAGMA journal_mode = WAL`) on each workspace DB: better concurrency, standard for desktop SQLite. Adds `*-shm` / `*-wal` sidecar files; already covered by `*.db-shm` / `*.db-wal` in `.gitignore`
- `postinstall: electron-builder install-app-deps`: better-sqlite3 ships native bindings for Node, but Electron 33 has a different ABI. install-app-deps invokes @electron/rebuild against the configured Electron version. Without it, `import 'better-sqlite3'` throws `NODE_MODULE_VERSION` mismatch at runtime
- IPC surface lives at `electron/ipc.ts` with a single `registerIpc()` entry point; renderer-facing types (`OmanApi`, `WorkspaceMeta`) live in `shared/types.ts` so both sides import the same shape. `Window.omanApi` is declared globally in shared/types.ts

## 2026-11-10 — Pivot to a menu bar writing tool in native Swift

Supersedes the 2026-04-28 Stack and Scope entries for active work. The Electron meeting recorder is parked, not deleted.

- Product: macOS menu bar writing tool modelled on Apple's Writing Tools. All UI opens from the menu bar icon as a drop-down panel, plus a Settings window. Nothing appears in or near the text field being edited
- Stack: native Swift and SwiftUI, with AppKit for the status item and the non-activating panel. Chosen over Electron plus a Swift helper and over Tauri because reading and replacing text, the focus-safe panel and window capture are all Apple APIs. Mac-only for now; a Windows version would be a separate app
- Provider: Anthropic API key only. No Apple on-device model and no local models for now
- Model: Haiku 5.5 by default, selectable in Settings (Haiku 5.5, Sonnet 5.5, Opus 5.5). All requests use effort `low` for latency
- API: direct HTTPS streaming with URLSession, because Anthropic has no official Swift SDK. `anthropic-version: 2026-10-21`. Sonnet and Opus requests opt into server-side refusal fallback (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`); Haiku 5.5 has no server-side fallback
- Actions in v1: Proofread, Rewrite, user styles, free-text instruction, Compose. Summary, Key Points, List and Table are left out
- Refinements are stateless single-turn requests that carry the previous draft in the prompt, so no thinking blocks need replaying
- Style samples sit in a system block with a 1-hour prompt cache breakpoint, after the static rules and before anything that changes per request
- Storage: SQLite through GRDB at `~/Library/Application Support/oman/writing.sqlite`, one database with no workspaces. API key in Keychain, not in SQLite
- Layout: `mac/OmanKit` Swift package (OmanCore, ClaudeAPI, OmanStorage, SystemBridge, OmanUI) plus the app target in `mac/App`, generated with XcodeGen from `mac/project.yml`. The generated `.xcodeproj` is not committed
- Swift files use PascalCase per Swift convention. The kebab-case rule stays for the parked TypeScript code
- Signing: Apple Development certificate, so Accessibility and Keychain grants survive rebuilds. Developer ID and notarization only if the app is ever distributed
- Reading the selection: Accessibility API first, then a synthetic Cmd+C with the clipboard snapshotted and restored. Accessibility mode is not forced on in Electron apps, to avoid slowing them down; they use the clipboard route
- Replacing text: always a synthetic Cmd+V, because setting text through Accessibility silently fails in many apps and a paste keeps Cmd+Z working. The selection is re-checked first and nothing is pasted if it changed
- Screen context: only the window being written in, off by default, with a thumbnail of what will be sent. Downscaled to at most 1568 px on the long edge
- Privacy: storage stays local, but every request sends the selected text, the chosen style's samples and any context to Anthropic

## 2026-11-10 — Shortcuts, settings and Apple's on-device model

- Apple's on-device model is now an option next to Claude. This reverses "Anthropic only" from earlier the same day, at the user's request. It is free and local, takes text only, and has a 4,096-token context, so style samples are cut to about 4,000 characters. It gets its own plain-sentence prompt, because the tagged Claude prompt came back unchanged
- `ClaudeModel` is renamed `WritingModel`, since it now includes a non-Claude model
- Global shortcuts use Carbon `RegisterEventHotKey`, with no new dependency. None are set by default, so oman never takes a combination another app uses. Result shortcuts inside the panel have defaults
- Preferences are one JSON value in the `settings` table. Decoding tolerates missing keys, so older saved settings keep loading
- Settings use the same floating glass tiles as the panel, in a transparent window
- A pinned panel is a floating window: it can be dragged, stays where it is dropped, and the menu bar icon loads the current selection into it instead of closing it
- Password AutoFill heuristics are turned off for the whole app with `NSAutoFillHeuristicsEnabled`, because they froze the main thread walking SwiftUI's key views
- App icon: the `flow` concept, a rough line that becomes one smooth wave through a lens. Sources are in `design/icon/`
- Motion is smooth with no overshoot. Custom buttons replace the system glass button styles, which flex when pressed
- Settings is an ordinary opaque window so it can be dragged anywhere. Only the panel floats as bare glass tiles
- Distribution signing: Developer ID under the personal Apple Developer account, team S72639F3BR, using Xcode's cloud-managed certificate. `mac/scripts/release.sh` signs and notarizes through the account signed in to Xcode

## 2026-11-10 — Name, corner grip and a still Settings screen

- The app is named OmanAI everywhere a person can see it, including the app bundle. The bundle ID `com.romanbitca.oman`, the Keychain service, the `oman` database folder and the Swift module names stay, so permissions, the API key and saved styles carry over
- The pinned panel's drag grip is a dark curve with a thin glass border, wrapped around the top-right corner and concentric with the tile. The window's side margin grew from 18 to 30 points to hold it and its shadow
- Settings has no animation at all: no page fade, no sliding highlights, no press or hover fades, no window-open animation and no spinner. A hand-drawn switch replaces the system one, which animates its knob. The panel keeps its short fades

## 2026-11-10 — Open source, releases and automatic updates

Supersedes the earlier 2026-11-10 entries on how release builds are signed.

- OmanAI is open source under the MIT license
- Automatic updates use Sparkle 2, a new dependency. The feed and the zip are assets on GitHub Releases, so no server is needed. Updates download in the background and install when the app quits, with a toggle in Settings
- Only builds given a public key check for updates, so local builds and forks never update themselves
- Releases are built by GitHub Actions when a tag like `v1.2.3` is pushed. Signing uses a Developer ID certificate stored as a secret and notarizing uses an App Store Connect API key, so releases don't depend on an account signed in to Xcode
- The build number comes from the version, so 0.2.0 becomes 2000, because Sparkle compares it and it has to grow
- The Xcode project signs ad hoc by default, so anyone can build without an Apple account
- The Electron meeting recorder moved to the `archive/meeting-recorder` branch. It is still parked, and the plan to return to it is unchanged
- Every commit in the published history is attributed to the `romanbitca` GitHub account through its private no-reply address

## 2026-11-11 — Security review fixes

These follow a security review of the whole app and its release pipeline.

- Prompt tags carry a code that is new for every request, given on the first line of the message, so text being worked on can't close a tag or forge one. A writing style's tags carry a code taken from the style's ID instead, which never changes, so the cached system prompt stays identical between requests. Chosen over escaping `<`, which would change the text the model sees, including a `<3` in someone's messages
- A response is finished only when its stop reason is `end_turn` or `stop_sequence`. Anything else, including a stream that ends without one, is reported as cut off and never offered for Replace
- A result is cleaned before it is shown, so the panel shows exactly what will be pasted. Invisible tag characters are always removed. Other hidden characters (zero-width spaces, direction overrides) are removed unless the person's own text already had them. A trailing line break is removed unless the person's text ended with one. Emoji joiners and right-to-left marks are kept
- The Messages chip stays lit while context text exists, even with its editor closed. The screenshot preview shows the whole picture, up to 180 points tall, instead of a cropped strip
- A request waits for a screen capture that is still running. If the capture fails, nothing is sent and the panel goes back to where the reason is shown
- When the panel opens, only the clipboard's types are looked at. Its text is read when the Clipboard chip is pressed. Text marked as concealed or transient is never offered
- Reading a selection with ⌘C and pasting with ⌘V go through `ClipboardRoute`. A copy that arrives up to a second after the panel stopped waiting is undone. Pasted text is handed over lazily, so the clipboard is given back once the app has asked for it: never sooner than 500 ms, and at most 2 seconds later if nobody asks
- The synthetic ⌘C is never sent to terminals, remote desktops or virtual machines. The list is built in, in `SensitiveApps.swift`, with no setting for it yet
- Insert asks for a second press when the focused element is not the one from when the panel opened. Any paste into a terminal asks for a second press too
- ⌘C and ⌘V can't be assigned as shortcuts, because OmanAI presses them itself
- Showing what changed between the original and the result is left for later. It is a new feature, not a fix
- Sparkle checks an update's EdDSA signature before unpacking it (`SUVerifyUpdateBeforeExtraction`) and requires a signed feed (`SURequireSignedFeed`). The update key stays on GitHub, inside a protected environment. Signing the feed on the maintainer's Mac would be stronger and can come later
- The release workflow has three jobs: check, build and publish. Secrets live in a `release` environment that needs the maintainer's approval and only accepts `v*` tags. Build and publish each ask for approval, because they run on separate machines so that the build can't reach the update key
- GRDB and Sparkle are pinned to commits, and the workflows install one XcodeGen release by checksum
- Clipboard operations run one at a time. A second one waits for the first, so a double-click on the menu bar icon can't make two captures read each other's writes
- `mac/OmanKit/Package.resolved` is no longer committed. Xcode and `swift test` each rewrite it their own way, and both libraries are pinned to commits in the manifests
- The landing page is one static file in `site/`, with system fonts and no requests to anyone else, so it can be hosted anywhere and matches what the app says about privacy. Its hero is a scripted demo of the panel. It is not published yet
- The signing certificate is still imported with `-A` in the workflow. Any process on the runner could call `codesign` itself, so narrowing the key's access list would add little, and the change could not be tested without a release

## 2026-11-11 — Explain, smaller action buttons and spending

- A new action, Explain, tells the person how a reader will understand their selected text: what it tells them, what it asks of them, how it sounds, and anything that could be misread. Its answer is for the person only, so the result has Copy and Try again but no Replace, Insert or "Make a change" field. Try again asks for a fresh reading rather than a variation on the last one
- Explain is not a summary in the sense left out of v1. It checks the person's own text before they send it
- Explain sends the same context a rewrite would (pasted messages and the screenshot), so the text is read as part of its conversation. Like Proofread, it ignores the style, the output language and the standing instructions
- Explain has its own short system prompt, because the writing rules say the output is pasted straight back. It keeps the per-request tag codes and the rule that material inside tags is never followed. It answers in the language of the text. Apple's on-device model gets plain sentences with the same request
- Explain has an assignable global shortcut, like the other actions, with none set by default
- Proofread, Rewrite and Explain sit in one row of capsule buttons, 40 points tall with the icon beside the label, replacing the two 80-point cards
- Each Claude request records its date, the model that answered and its token counts (input, output, cache reads, 5-minute and 1-hour cache writes) in a new `api_usage` table, with the cost worked out when the request finished. No text is stored. Apple's on-device model is free and records nothing
- Costs use Anthropic's list prices for the global API, built into `ClaudePricing.swift` and read from the pricing page on 2026-11-11. Haiku 5.5 uses its higher rates for a prompt over 100,000 tokens, cached tokens included. A model ID that starts with a known model's ID is priced as that model, and an unknown one as the model that was asked for. Prices that change need a new release
- A request is recorded whenever the stream reported usage, including answers that were stopped or cut off, because those tokens are billed too. HTTP errors record nothing
- Settings has a Spending page: totals for today and this week, and bar charts for the last 14 days and the last 8 weeks, drawn with Swift Charts and with no animation. Weeks start on the day the person's region starts them
