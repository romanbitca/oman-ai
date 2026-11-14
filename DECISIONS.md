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

## 2026-11-11 — Apple's Writing Tools off inside OmanAI

- The panel and Settings turn off Apple's Writing Tools for their own text, with `writingToolsBehavior(.disabled)` on macOS 15 and later. OmanAI is a writing tool itself, and the system's floating Writing Tools button appeared beside selected text in the panel, where it could cover Back and take its clicks
- Back writes one line to the system log (subsystem `com.romanbitca.oman`, category `panel`) naming the screen it went to, and no text, so a Back that seems to do nothing can be checked against one that never arrived

## 2026-11-11 — The panel looks like Control Center

Supersedes, for the panel, "Custom buttons replace the system glass button styles, which flex when pressed" from 2026-11-10. Settings is unchanged and still has no animation.

- While the panel is open from the menu bar, a backdrop dims and slightly blurs the side of the screen it is on, fading out beyond it, as behind Control Center. It is a separate window that ignores the mouse, so a click beside the panel still reaches the app there and closes the panel. It goes away while the panel is pinned
- The backdrop is a behind-window blur (`NSVisualEffectView`, full-screen UI material, dark) with a gradient mask, under a black gradient at 22%. The blurred picture is laid over the sharp one at 75%, which keeps the blur slight. AppKit has no lighter blur radius
- With the theme set to Match system, the panel is dark, with white text, as Control Center is in light mode too. A theme chosen in Settings still applies
- Over the backdrop the tiles are clear glass. Pinned, or with a light theme, they stay regular glass, because dark text on clear glass over an unknown background could get lost. Tinted glass is never clear
- Buttons in the panel use Apple's interactive glass, which lights up under the pointer and flexes when pressed, at the maintainer's request ("as much close to native as possible"). Their labels no longer dim when pressed
- A chosen style and a context chip that is on are white with black text, as an "on" toggle is in Control Center, instead of purple
- Clear glass gets a 2% white fill in its own shape, because glass that adds no alpha to the window lets a click through to the app behind

## 2026-11-11 — No backdrop, frosted glass again

Supersedes the backdrop and clear-glass points of "The panel looks like Control Center" above.

- The maintainer installed 0.3.1 and found it looked very bad. Over a white app the backdrop came out as a gray veil across half the screen with no visible blur, and clear glass let the app's text show through the tiles. Both are gone
- Tiles are regular, frosted glass again. Kept from 0.3.1: the dark panel with white text when the theme is Match system, Apple's interactive glass on buttons, and white "on" chips

## 2026-11-11 — Matched against Control Center on screen

Supersedes "No backdrop, frosted glass again" for the panel's glass. Settings keeps frosted glass and no motion.

- With the maintainer's permission, the panel and the real Control Center were shown in the top-right corner and captured on four backgrounds: a white app, a dark app, a bright gradient and the desktop. The choices below came from comparing them side by side
- Tiles are clear glass, as Control Center's are
- The style and context chips sit together in one glass tile, as a Control Center module holds its toggles, so an app's text never shows between them. Inside it they are flat: translucent when off and solid white when on. Outside a tile an "on" chip is solid white too, because tinted glass turned gray over dark backgrounds
- A soft-edged blur built into the panel's window covers what is behind the tiles and fades out 22 points beyond them, in place of the blurred backdrop behind Control Center. It uses the `fullScreenUI` material in the system's light or dark mode. Control Center's backdrop is a pure blur, which no public API offers, and the public materials add a tint: over a dark app in light mode the panel sits on a light frosted card where Control Center stays dark. At less than full strength sharp copies of the app's text showed through, so the blur is always at full strength
- A click on the blur's soft edge closes the panel, as a click beside Control Center does, because the panel's window takes that click. A pinned panel has no blur, because it would cover the drag grip
- A disabled button in the panel dims only its label, as on macOS, instead of fading its glass

## 2026-11-11 — Backdrop and glass set by measuring Control Center

Supersedes the backdrop and glass points of "Matched against Control Center on screen" above. The maintainer rejected that version, a blurred card behind the panel, as a box that was not really transparent, and a wider band of glass tried after it because it blurred everything.

- Control Center was measured on macOS 27 with a checkerboard behind it. Around its modules it blurs what is behind by about 3 points and darkens it by 10%, with no tint: white becomes 90% and black stays black. The blur is full 45 points inside the modules' outline and gone 40 points outside. The darkening is full 34 points inside and gone 126 points outside. Through a tile, white is 73% and black 13%. `PanelBackdropLayout` holds these numbers
- The backdrop uses the window server's own blur, `CGSSetWindowBackgroundBlurRadius`, because no public material or glass blurs without tinting. It is a private call, the one iTerm2 and Ghostty use for see-through windows. It is looked up at run time: without it the panel keeps frosted glass and has no backdrop
- That blur is all or nothing inside a window's shape, so the soft edge is six nested windows whose small blurs add up to 3 points. A seventh window carries the darkening. None of them takes a click or covers the menu bar, and they follow the tiles as the panel changes height
- Tiles are clear glass with a 29% layer of 13% gray over it, which gives Control Center's 73% and 13% exactly
- Text to read or type stays on frosted glass: the result, the compose box, pasted context, setup and errors. Control Center shows no paragraphs, and long white text over a slightly blurred app is hard to read
- Pinned, with the Light theme, or with Reduce Transparency on, every tile is frosted. Pinned or with Reduce Transparency on there is no backdrop either
- Tiles are 12 points apart with a 26-point corner radius, up from 8 and 22, closer to Control Center's 13 to 14 points and its rounder modules

## 2026-11-11 — Tile colour and focus set by measuring Control Center

Supersedes the tile point of "Backdrop and glass set by measuring Control Center" above. The maintainer liked that version in general, but found the tiles too dark and not glassy enough next to Control Center, and saw the panel turn darker when it lost focus.

- Control Center's tiles were measured again, on plain colour fields. Grays follow the same law as before: through a tile, white is 73% and black 13%. Colours come out more vivid than what is behind the tile, about 1.25 times as far from gray. A red that reads 81/27/18 (red, green and blue in percent) behind a tile reads 89/24/11 through it. The gray layer over our glass did the opposite and cut colour by a third, to 72/31/23
- The layer over clear glass is now 30% of 13% gray drawn with a luminosity blend, so it sets a tile's brightness and leaves colour alone, and the panel adds a saturation boost of 1.25. Through a tile the panel reads 13, 44 and 73 on black, mid-gray and white, against Control Center's 13, 43 and 73. On red, orange, blue and green it reads 87/23/10, 80/46/0, 11/37/95 and 0/60/15, against 89/24/11, 84/46/0, 15/37/91 and 0/60/15
- The boost goes on the whole panel, not on each tile. The tiles share one glass container, which draws the glass for all of them, so a boost on one tile never reaches its glass. Frosted tiles get it too. Pictures that must keep their own colours, the app's icon and the screenshot preview, undo it for themselves
- Without clear glass there is no boost. Pinned, with the Light theme, or with Reduce Transparency on, the panel looks as before
- The panel keeps one look whether or not it has the keyboard. macOS draws glass darker and flat in a window that isn't key, and turns a tinted button gray. A pinned panel sits beside the app being typed in and is rarely key. The panel's window answers AppKit's `hasKeyAppearance` with yes. That method isn't in the public headers. SwiftUI's own switches for this, `appearsActive` and `controlActiveState`, were tried first and don't reach glass

## 2026-11-11 — A smooth panel: matched tiles, a cheap glow and a backdrop that fades

Supersedes how the backdrop is drawn in "Backdrop and glass set by measuring Control Center" above, and the glass container the panel's tiles sat in. The maintainer found a click laggy, saw a straight line where the blur began, and asked for a very fast and smooth animation.

- Everything here was decided by measuring: a counter of how many of the display's refreshes the main thread answers on time, and the share of a processor core in use, in an optimised build on a 120 Hz display
- The panel's tiles are no longer in Apple's glass container. With it a screen change ran at 34 frames a second; without it at 111 to 119. The container costs that much whatever its spacing, and whether or not tiles carry glass identities. Settings keeps its container, since nothing moves there
- A tile with an identity now moves and resizes into the tile with the same identity on the next screen, by matched geometry. The style and context tile has an identity too, so it slides instead of showing twice
- What is on the tiles swaps in 0.12 seconds while the tiles take 0.26 to settle. With one timing for both, the old and the new screen were readable on top of each other for most of the change
- The glow around the tile while Claude writes is a Core Animation layer that turns behind a still edge. Drawn by SwiftUI for every frame it kept the main thread 99% busy for as long as the answer took; now it is 1%. It looks the same, checked side by side
- The backdrop is one window with one layer, Core Animation's own backdrop layer with a blur whose strength varies from spot to spot, and the darkening over it. The seven stacked windows it replaces could only blur all or nothing, so their blur began in steps, each a visible line. The new blur measures half a point 30 points from the tiles and one point 14 points from them, as Control Center's does, and 3 points behind the tiles. It also fades in with its window when the panel opens, instead of appearing at once
- `CABackdropLayer` and `CAFilter` are not in the public headers. They are looked up at run time; without them, or before macOS 26, the panel keeps frosted glass and no backdrop. This replaces the private window-server call, which is no longer used
- The panel arrives with a fast fade and a drop of 8 points from the menu bar. Growing into place, as Control Center does, was tried and halved the frame rate while it played, because glass is drawn again for every size and only moved for a slide
- Closing stays immediate. Fading out would keep the keyboard in the panel for longer, and putting text back into the app depends on that hand-over

## 2026-11-11 — Templates and context are choices, and the panel hangs lower

Asked for by the maintainer after 0.3.3. Supersedes "The Messages chip stays lit while context text exists" in the security review fixes above.

- The panel's window hangs from the menu bar's lower edge, with the gap to the first tile inside it. The first tile starts 12 points below the bar, where Control Center's first module starts. It used to hang from the icon's own box, which ends 6 points above the bar's edge, so the first tile began 1.5 points under the bar
- A style chip only chooses the template. It no longer rewrites at once. Exactly one is chosen, and the first chip, As written, is no template: the person's own voice, as it shows in what they wrote. The maintainer picked the name from a short list
- Proofread, Rewrite and Compose use the chosen template. Explain never does, because it only reads
- Proofread with a template still only corrects, but takes the template's habits with capital letters and punctuation as correct, in both directions. It still sends no context, and the standing preferences still don't apply to it. With As written it works as before
- Rewrite with As written is told to keep the writer's own voice: their formality and their habits with capital letters, punctuation and emoji
- A style's global shortcut is an action of its own and still rewrites at once
- The template an app was last written in is remembered when it is used, not when it is chosen. After As written nothing is kept for that app, so its next panel starts on the default template from Settings, or on As written without one
- Screen, Messages and Clipboard are switches, and any of them can be on together. Messages on shows the box and sends what is in it; off hides the box and sends none of it, though the text is kept. Clipboard on reads the clipboard at that moment, shows all of it and sends it; off drops it. So only what is switched on is sent, and everything switched on is on show

## 2026-11-11 — As written, one line of templates, and a new menu bar icon

Chosen by the maintainer from proposals, after trying the preview.

- The first chip is named As written. It stays at the start of the row, with a thin line between it and the templates
- The templates stay on one line. When there are more than fit, the line scrolls sideways under a fade at its right end, and it opens scrolled to the chosen template. Wrapping made the panel taller with every template
- The Screen chip is the only control for the screen: it turns on and off like Messages and Clipboard. The picture that will be sent is still shown while it is on, because everything switched on is on show, but it no longer has a remove button of its own
- The menu bar icon is one wave drawn as a single stroke, the seventh of eight ideas shown. It replaces the app icon's shape traced down to menu bar size

## 2026-11-11 — Settings in macOS's own design

Chosen by the maintainer from two prototypes, a sidebar as in System Settings or tabs in the toolbar as in Safari and Mail: tabs in the toolbar, with macOS's own controls and their own motion. Supersedes "Settings has no animation at all" and the glass tiles Settings was drawn with.

- Settings is a window with a tab for each page in its toolbar: General, Writing, Styles, Shortcuts, Key & Permissions, Spending. About is gone. Updates are a section of General, and the version, the link to GitHub and Quit end that page
- Every page is a grouped form with the system's toggles, pop-up menus, segmented controls, text fields and buttons, in the system accent colour. None of the hand-drawn controls remain, nor the switch that kept them still
- The window is 600 points wide and as tall as the page it shows. It changes height from its top edge in 0.2 seconds when the page changes. A page taller than 620 points, or than the display leaves room for, scrolls instead
- A style is edited in a sheet. The box for a new message comes first and the newest message lands right under it, so adding several needs no scrolling. Try it is fixed at the bottom of the sheet, so a long list never pushes it out of sight
- Deleting a style asks first, in macOS's own alert with Cancel as the button Return presses, because a style and its messages can't be brought back. Before, one click on a bin deleted it
- The default style can be As written
- A shortcut that isn't set reads Record Shortcut. How a shortcut is recorded is unchanged, and recording stops when the page or the window is left
- The model is a pop-up menu. Choosing one that can't be used leaves the choice where it was and says why

## 2026-11-11 — Spending by period

Asked for by the maintainer: more than today and this week, such as this month, last month and all time.

- The Spending page has one period control: Today, This week, This month, Last month, All time. It sets the total, the chart and the list by model together
- The total comes with the number of requests, the tokens sent and received, and the average cost of a request
- The chart has a bar for each hour of today, each day of a week or month, and each month of all time, including those with nothing spent and those still to come. All time starts at the first request and shows at least six months
- By model lists every model ever used, most expensive over all time first, and keeps that list in every period, so the page stays the same height from one period to the next
- All of it is worked out from the stored requests when Settings opens or the page shows. Nothing new is stored

## 2026-11-11 — Apple's model is told to copy casing, not to use capital letters

- Proofread with a template on Apple's on-device model is told to "copy this person's casing and punctuation habits" and to "fix the typos in this text and change nothing else". The wording written that morning, "use capital letters and punctuation the way this person does", made the model answer in capitals throughout. It had not been released
- Seven wordings were run on the model itself, twice each on up to four texts, before choosing. The chosen one keeps a lower-case style lower-case and capitalises for a style that does

## 2026-11-12 — A website with documentation, on the maintainer's own server

Asked for by the maintainer: a richer site with recordings, examples and motion, a page that explains every button, a fuller README, and a Donate button.

- The site is static files in `site/`: a home page and `site/docs/`. No build step, no libraries and nothing loaded from anywhere else. Its one outside request asks GitHub for the latest version number, and it works without the answer
- It is served by nginx from `site/Dockerfile`, on the maintainer's Coolify server at oman-ai.romanbitca.com. Coolify builds it from `main` and deploys again when a file under `site/` changes
- The design is one dark page: large type, the app's own glass, and the app itself at work. A first version with a light body, a rounded display face and bordered cards was turned down by the maintainer as dated. The second was drawn after looking at how Raycast, Linear and Wispr Flow present Mac apps in late 2026
- The recordings and pictures are of the real app: its real panel and Settings, driven by the test harness over a made-up desktop with a stand-in chat window. Nothing in them comes from the maintainer's screen
- Every speed and cost on the site, in the docs and in the README is measured: averages over 11 short writing tasks at the Fast setting, through the app's own client, on 12 November 2026
- The response headers allow scripts, styles, pictures and recordings from the site itself only. That also blocks the analytics script Cloudflare tries to add to pages on this domain, so the page's statement that it has no analytics holds
- Donations take one address: the `data-donate-url` attribute on the home page's `body`. Until it is set, Donate leads to the support section, which says donations open soon. The maintainer plans a PayPal link

## 2026-11-12 — Proofread thinks first, and the app counts the habits itself

Made overnight by the assistant, while the maintainer was away, after measuring real answers. The first two points change what a person sees: Proofread is about a second slower on Haiku, and As written now keeps lower case. The maintainer read both the next morning and said to merge them and release them as 0.3.5.

What was measured: 17 kinds of short text, each asked several times of Haiku, Sonnet and Opus at Fast, Balanced and Best through the app's own client, with every answer graded by checks on its text. With the prompts of 0.3.4, 90 of 432 answers failed a check. Haiku at Fast, the default, failed 32 of 80: it left out apostrophes a template uses, spelled out "u" and "gonna", added "Best, Roman" to a proofread, opened an explanation with "You wrote this in English, so I'll answer in English", and answered a Romanian text in English. With the prompts below, 4 of 459 failed. On ten further kinds of text that were never looked at while the wording was tuned, 31 of 80 answers failed before and 1 of 80 after.

- Proofread asks Haiku and Sonnet for their highest effort whatever quality is set, opens with "This task needs care more than speed: think it through before you write", and is not told to answer at once. Haiku does not think at all at low effort, with or without that line, and without thinking it got about one proofread in four wrong whatever the wording. Thinking first it got none wrong in 80. On Haiku a short proofread now takes about 1.7 seconds, not 0.9, and costs about $0.0002, not $0.0001. Sonnet barely changes. Opus thinks at every effort and keeps the person's setting. Settings says under the quality control that Proofread always takes the time to check
- The app counts a template's habits and states them, instead of asking the model to work them out from the samples: whether sentences start in lower case, whether a message ends without a full stop, and whether apostrophes are written or left out. Asked to work that out while writing, the models got it wrong in about half of their answers. The count is in `WritingHabits.swift`. A list of English contractions without apostrophes (dont, cant, im) is only used when the samples are in English
- Proofread with As written goes by the text itself. Where most of its sentences start in lower case, the case of every letter and the sentence punctuation stay, and only spelling, grammar and missing apostrophes are corrected. Otherwise capital letters and punctuation are corrected too, so a missed capital in a formal email is put right. This supersedes "With As written it works as before" above: before, Haiku mostly kept lower case, Opus always capitalised, and some answers capitalised half of a message
- Chat shorthand such as u, thx or gonna stays in a proofread. It is wording, not a mistake
- The style block ends by saying the samples are the person's own messages and that the name they sign with is part of the voice. How to use the samples is said by each task. Told in the style block to match greetings and sign-offs, a proofread came back as an email with a sign-off added; told only to take "never their content or facts", Haiku signed emails "Best," with no name
- Explain is told that the panel shows every word, so it writes only the reading: no notes to itself, no restating or translating, nothing about the language. "You" is always the writer. It is told not to search for faults: for a plain request Sonnet and Opus had always found two or three, such as "by Friday doesn't say what time"
- Explain names the language to answer in. The app works it out on the Mac with Apple's language recogniser, and says nothing when the text is too short to tell. Nothing is sent anywhere for this
- The writing rules say to write the text once and never to start over or comment on the answer. This is a precaution: the one answer that did so under the old prompts was a proofread, which is now fixed at the root, and no rewrite or new text did it in about 500 answers
- `LiveWritingTests` keeps this measurement in the repository: 29 kinds of text with their checks, two of them with a picture attached as the Screen switch attaches one. It runs only when `OMAN_LIVE_KEY` holds a key, and fails when more than 1 answer in 20 fails a check
- The Spending chart's labels use Charts' aligned preset, which centres each under its bar and keeps the first and last on the chart. They used to start at the bar, which cut "29 Nov" off in a 30-day month and dropped the newest month's label from All time once there were more than twelve
- The website's container is built on nginx's stable line, pinned to the exact image by its digest. It had been built on 1.29, a line that stopped getting updates in April 2026. This one was deployed the same night, because the site is public

## 2026-11-12 — The website is light, with glass, and its header shows the app at work

Asked for by the maintainer after seeing the dark page: no black theme, a header with a video or a set of animations on its right, and more glass, the way Apple uses it. The rest of the page was to stay as it was.

- The page is light. Soft colour stays fixed behind it, and the menu, the cards, the tiles and the second buttons are sheets of glass that blur it as they scroll past. This supersedes "The design is one dark page" above
- The main button is the violet of the panel's own Replace button. Teal marks what is on or done
- The header has the words on the left and recordings on the right: the real panel close up in a slab of glass, one recording after another, with names to choose one and a button to pause. There are four, in the order of the list under Use cases: Rewrite, Proofread, Explain and Compose. Until 0.3.6 was filmed there were three, without Proofread
- The header's recordings are cut from the same raw footage as those under Use cases, cropped to the panel, so they are sharp at that size. The chat under the panel is drawn by the page from each recording's own texts, and changes on the frame where the recording pastes. The line under the recordings says which part is which
- With motion turned off, or without scripts, nothing plays and a still picture of the result is shown
- Settings is shown in its light pictures on the site and in the documentation. The README keeps both
- Style sheets and scripts are kept by browsers for an hour, so their addresses carry a number (`?v=3`) that goes up with each redesign
- The server's proxy no longer compresses what the site sends. It had gzipped the recordings too, and a gzipped file cannot be asked for in parts, which Safari needs before it plays a video. The site's own nginx compresses the text, as its config says. The setting is "Enable gzip compression" on the app in Coolify, now off. The recordings got new file names, because Cloudflare keeps the gzipped copies of the old ones for a week

## 2026-11-12 — Proofread shows what it changed, at once or when asked

Asked for by the maintainer: a way to see what Proofread changed, with a few ways offered to choose from. Four were drawn for them: marks in the text, highlights first, the original in a box above the result, and a list of changes. They chose the first two, and asked for both with a choice between them in Settings.

- The panel compares the person's text with the corrected one word by word, on the Mac, so nothing more is sent anywhere. The texts are cut into words, runs of spacing and single marks, and compared with Swift's `difference(from:)`. The code is `TextChanges.swift`
- Settings, under General, has "Show what Proofread changed". At once tints each changed word as soon as the result appears, and the header shows their count; clicking it shows the words they replaced, struck through just before them. When I ask keeps the result plain until Show changes is clicked
- At once is the default. The assistant chose it because it shows the changes without a click; the maintainer asked for both and named no default
- After a proofread the header shows this button where Show original was, and ⌘O does the same. It says "No changes" when nothing was corrected. When more than half of the words changed, counting both texts and in a text of at least 16 words, marks would cover everything, so Show original stays. Rewrite and Explain keep Show original, because their results are meant to differ from the text
- A word keeps its apostrophe, an emoji stays whole, and in scripts written without spaces between words, such as Japanese, Chinese and Thai, each character stands alone, so one corrected character doesn't mark a whole sentence. A change of spacing alone is neither marked nor counted. A word replaced by another counts as one change, and changed words next to each other count one each
- Replace and Copy deliver the corrected text, never the marks. While the old words are on show the text can't be selected, so a selection never mixes the two texts
- New words are tinted green, and old words are red and struck through. With Differentiate without colour turned on, new words are underlined too. VoiceOver reads each change by name

## 2026-11-12 — The website has 9h Digital's chat assistant

Asked for by the maintainer, who gave the code to embed.

- Both pages load the assistant from `ai-chatbot-staging.9hdigital.com`, with the site key the maintainer gave. The response headers in `site/nginx.conf` allow scripts and connections from that address, and still from nowhere else apart from the site itself and GitHub. This supersedes "nothing loaded from anywhere else" above
- The assistant asks its server for its settings and sends each chat there. It sends no cookies, and keeps a little of its own data in the browser's local storage. The footers say that what a visitor types into it goes to 9h Digital
- Its address is the assistant's staging server, which accepts requests from this site's address. A move to another server needs the new address in both pages and in `site/nginx.conf`
- Cloudflare's analytics script stays blocked

## 2026-11-12 — Dictation on the Mac, from a shortcut or the panel

Asked for by the maintainer, after the free dictation app Handy: light, words shown live while speaking, a choice of model and of language, every transcript to look back at but no old recordings, a separate shortcut for a long dictation rather than Handy's tap-or-hold on one key, the pill's position chosen in Settings, and dictation inside the panel too. They asked the assistant to decide the rest itself, so the choices below not named above are the assistant's.

- Three models, all on the Mac, so the sound never leaves it. Apple's speech model is the default. It uses SpeechAnalyzer: its newer `SpeechTranscriber` where that knows the language, otherwise `DictationTranscriber`, the model behind macOS's own dictation. On macOS 27 that is 68 languages, one at a time, and macOS downloads each language itself. Parakeet is Moondream's Parakeet Ultra, a post-training of NVIDIA's parakeet-tdt-0.6b-v3 (CC BY 4.0), run by FluidAudio: 25 European languages, which it works out itself and can't be told. Whisper is OpenAI's large-v3 turbo in Argmax's 626 MB Core ML build, run by WhisperKit: about a hundred languages, chosen or worked out. Parakeet and Whisper are downloaded from Hugging Face only when the person asks, into `~/Library/Application Support/oman/SpeechModels`, and Remove deletes their folder. This widens "no other model provider" to speech models that run on the Mac; nothing is sent to a speech service
- The language list follows the model, with Automatic first where the model can work the language out, as Handy does. Each model keeps its own choice
- Live words: Apple's model sends a guess at the newest words and settles them; FluidAudio decodes the last seconds again every second; Whisper reads the unsettled sound again each second, and all but its last two stretches then count as settled. Silence before anything is said is not given to Whisper, which tends to make words up for it
- Two global shortcuts, empty at first like the others: Hold to dictate, which puts the words in when the keys are let go, and Start or stop a long dictation. Global shortcuts now also report when their keys are let go. Escape cancels; it is taken as a shortcut only while a dictation runs, beside the others, so a held shortcut isn't disturbed. Cancel is always Escape, as in macOS's own dictation
- While the person dictates into another app, a glass pill shows the live words, the newest in view, with the app's wave moving with the voice and a check button to finish a long dictation. It hangs under the menu bar icon, or sits at the bottom of the screen when Settings says so. The bottom of the screen is the maintainer's choice and the one place something appears away from the menu bar; it is still nowhere near the text field. The pill never takes the keyboard, and the words are pasted at the cursor the way Insert pastes. When there is nowhere to paste they are copied, and the pill says so
- The menu bar icon's wave moves with the voice during a dictation, and clicking it finishes the dictation
- In the panel, the words go into the field being typed in, as they are said: "Describe your change", "Make a change…" or Compose's request. Each has a microphone button, and the shortcuts do the same while the panel has the keyboard. Escape puts the field back as it was
- Settings has a Dictation tab: model, its download with size, progress, Cancel and Remove, language, the shortcuts, where the pill shows, the microphone permission, Keep transcripts, and the transcripts with Copy and Delete. The microphone is the Mac's input, chosen in System Settings, Sound; the tab has no choice of its own, to stay short
- Kept transcripts are text only, in a `dictations` table: the words, when, how long, the model, the language and the app they went to. This supersedes "never its text" in the privacy decision above, for dictations alone, and Keep transcripts turns it off
- The app asks for the microphone with `NSMicrophoneUsageDescription`, and release builds carry `com.apple.security.device.audio-input`, which the hardened runtime needs. Apple's speech model needs no speech recognition permission
- FluidAudio 0.18.3 (Apache 2.0) and WhisperKit 1.1.1 (MIT, from `argmax-oss-swift`) are pinned to their release commits. FluidAudio is used with no package traits, so its voices, speaker separation and prebuilt text normaliser are not built in. That needs Swift tools 6.2, so OmanKit's manifest moves to 6.2

## 2026-11-12 — The dictation pill has two looks, chosen in Settings

Nine looks were drawn as moving mockups. The maintainer turned down the first four, asked for Done to sit outside the box with the words, then chose two of the next five, with Card changed as they described.

- Card: a row with the moving wave in a glass circle, the seconds in a glass capsule and, for a long dictation, Done in a glass circle at the far end; the words below it in a glass card. This supersedes the pill described in the dictation entry above, with its wave and check button inside the box
- Floating: the words float on a soft blur and darkening of what is behind, fading out at the edges, with no box; below them a glass capsule with the wave and the seconds, and Done beside it. The blur is the panel backdrop's tint-free one; on a Mac without it, only the darkening shows
- Done is only there for a long dictation; letting go of the keys finishes a held one. Escape still cancels, so neither look has a cancel button
- Settings, under Dictation, has Look with Card and Floating. Card is the default, being the one the maintainer liked first

## 2026-11-12 — Dictation: models that stream, a list to choose from, and Settings in parts

The maintainer tried a signed test copy with the microphone. It worked, but with Parakeet Ultra the first words came about 10 seconds after they were said, since FluidAudio's live mode for it decodes 11-second windows. They showed how Handy lists its models and settings, asked for the same kind of list, for the Dictation page in parts with a picture of each look, for the shortcuts to move to the Shortcuts tab, for a word list and for unloading the model, and for a cancel button beside Done.

- Two models that stream are added, both NVIDIA's, run by FluidAudio and downloaded from Hugging Face: Parakeet Unified, English only, which Handy uses (CC BY 4.0), set to answer 0.64 seconds behind the voice; and Nemotron Unified, in Parakeet's 25 European languages, told the language or working it out (OpenMDW 1.1), set to answer 1.12 seconds behind. Each latency is a separate download, and these are the tiers the library measures as best for the work they take
- Parakeet Ultra no longer uses FluidAudio's windows: while the person speaks it reads everything said so far again about every second, which it does more than a hundred times faster than speech, and once more at the end. Whisper keeps its own reading again of what isn't settled
- Settings lists the five models as Handy does: name, Live for the three that stream, a line about it, the person's own languages ticked where the model knows them, speed and size, with Download, its progress, and Delete. The person's languages are the ones macOS lists in Language & Region, so there is no setting for them. A click chooses a model; one still to download is downloaded first, then chosen. Deleting the chosen one goes back to Apple's
- Settings' Dictation page is in four parts, chosen at the top: Model, Look, Words and Transcripts. Look has a drawing of each look to choose from. The dictation shortcuts move to the Shortcuts tab, and the microphone to Key & Permissions with the other permissions. This supersedes the layout of the Dictation tab described above
- The person's own words, such as names, are written their way in what is dictated: a match ignores case, spaces and punctuation, a word of five letters or more also matches with a letter or two different, and up to three spoken words can make one. Apple's model and Whisper are also told to expect them. FluidAudio's own way of boosting words needs a further model, so it isn't used
- Remove filler words takes out um, uh and the like where they stand alone, and is on at first, as in Handy
- A downloaded model stays loaded for the next dictation and is unloaded after 5 minutes without one, to free its memory; Settings offers right away, 1 minute, 15 minutes, an hour and never. macOS looks after Apple's model
- Both looks get a cancel button beside Done for a long dictation; Escape still cancels either kind

## 2026-11-12 — Dictation starts at once, and the words arrive smoothly

The maintainer found the first dictation after launch slow, as if frozen, and asked for a loading sign, for the words to grow to about ten lines, and for words to arrive with an animation rather than pop in.

- Measured: the first time a downloaded model loads in OmanAI, Core ML prepares it for the Neural Engine, which took 23 seconds for Parakeet Unified. macOS keeps the result in OmanAI's cache folder, so every load after that, in a new launch too, took about 0.2 seconds. That first preparation normally happens at the end of the download in Settings, which now says Preparing meanwhile; the test copy met it at its first dictation because its models were put in place by hand
- The chosen model is loaded a few seconds after launch and whenever the model or its language changes, then unloaded after the time Settings gives, unless that is right away
- The microphone starts the moment a dictation starts, before the model is ready, so nothing said while it loads is lost; its words follow once the model is ready. Meanwhile the pill shows a spinner and "Getting Parakeet Unified ready…", with the model's name
- The words grow from one line to ten, and then scroll to keep the newest in view. This supersedes the three lines above
- Each word fades in from a slight blur and a little below its place as it arrives, and the area grows smoothly with them. With Reduce Motion on, words only fade in

## 2026-11-12 — Dictation with Option or Command alone, ten models in plain words, and the ✨ button

The maintainer asked for: Copy last transcript in Compose, more of Handy's settings, Transcripts first, a very light red cancel button, hold-to-dictate and the long dictation bound separately to Left or Right Option or Command, a model list that looks less like Handy's, more models, no speed bars that people can't read, a button that takes dictated words to the panel's Proofread, Rewrite and templates, and then a release with the website and documentation brought up to date. They asked the assistant to decide the rest, so the choices below not named above are the assistant's.

- Option or Command on its own: under each dictation shortcut in the Shortcuts tab, "Or hold a key on its own" and "Or tap a key on its own", each None, Left or Right Option, or Left or Right Command, beside the key combinations. OmanAI watches the keys through macOS's event monitors, which work with the Accessibility permission it already has. A hold starts 150 milliseconds after the key goes down, so a quick ⌥E stays a shortcut. Another key, Shift, Control or another Option or Command while it is down makes it part of a shortcut: nothing starts, and a hold that had started is thrown away. A press shorter than 0.35 seconds is a tap. With the same key for both, a tap starts a long dictation and holding it dictates until it is let go
- Four more models, each read again about every second like Parakeet Ultra, all downloaded only when chosen: Parakeet TDT v2, NVIDIA's English Parakeet (CC BY 4.0); Whisper Large v3, about a hundred languages (Apache 2.0, in Argmax's 947 MB Core ML build); Parakeet Redux, Moondream's smaller re-training of Parakeet v3 (CC BY 4.0, macOS 15 or later); Whisper Small (Apache 2.0, 216 MB). This widens the three models of the first dictation entry and the five of the later one to nine
- NVIDIA's Canary 1B v2 was tried and left out. FluidAudio calls its build a beta, it needs macOS 15, and the first time it loaded, macOS spent more than 15 minutes preparing it for the Neural Engine on an M1 Pro without finishing, while Settings would only have said Preparing. Its 25 languages are those of Nemotron Unified and Parakeet Ultra
- The list no longer copies Handy's: no language badges and no bars. The models sit in three groups, each with a line saying what it means: Live (Apple, Parakeet Unified, Nemotron Unified), Accurate (Parakeet Ultra, Parakeet TDT v2, Whisper Large v3, Whisper Large v3 Turbo) and Small (Parakeet Redux, Whisper Small). Each row has a round choice mark, the name, a line about it and one line of facts in words: how soon its words show, such as "Words as you speak" or "Words a moment later"; its languages as a phrase that names the person's own, such as "25 languages, including English but not Japanese" or "English only"; and its size. Download shows its percentage and then "Preparing…"; a downloaded model has a ⋯ menu with Delete Download; one that can't run here says "Needs macOS 15". The chosen model's language and when to free its memory now sit above the list. This supersedes the list "as Handy does" in the earlier entry
- Settings' Dictation page is in five parts, Transcripts first and on show when the page opens, then Model, Look, Words and Sound
- Taken from Handy's settings, as fits a writing tool: how many transcripts to keep, none, the last 10, the last 50 or all, which replaces Keep transcripts; a microphone of the person's choice, used while it is connected, otherwise the one in System Settings, which supersedes "the tab has no choice of its own" above; a sound when listening starts and stops, macOS's Tink and Pop; muting the Mac while listening, undone afterwards only if OmanAI did the muting; a space after the words; and Return or ⌘Return pressed after the words go in, never when they could not go in. All are off at first. Not taken: Handy's paste and clipboard options, translation to English, start hidden and its model-specific settings
- The ✨ button sits between Cancel and Done in the pill, for a long dictation into another app. It finishes the dictation and opens the panel with the words, as if they had been selected: Proofread, Rewrite, a template, Explain, or Compose with them as reference. They aren't in the app yet, so the result goes in at the cursor with Insert rather than replacing anything. The transcript is kept as usual
- Copy last transcript sits at the bottom left of Compose when there is one: the last dictation since OmanAI started, or else the newest kept transcript. It says Copied for two seconds
- The pill's Cancel button is the faintest red: red glass at 13% and a pale red cross. Done and ✨ stay plain glass
- The next release is 0.4.0, since dictation is a new part of the app

## 2026-11-12 — Spending shows the fixes put back beside what was spent

The maintainer asked for every bar on the Spending page to be split in two, the fixes applied to text and the money spent, with more details on hover, and for the page to be "even more advanced". They asked the assistant to decide the rest, so the choices below are the assistant's.

- A fix is a text OmanAI wrote that was put back into an app with Replace or Insert, with any model, Apple's included. Every text written is noted too, so the page can say how many of them were kept
- Each written text is kept as a row in a new `writing_actions` table: when, what for (Proofread, Rewrite, Explain or Compose), the model, the app's name and whether it was put back. Never its text. A change asked for, or Try again, is another text of the same kind; only the one put back counts as a fix. Claude's requests also note their kind, in a new `kind` column of `api_usage`, so cost can be split by action; requests from before have none and show as "Earlier requests"
- Each hour, day or month has a pair of bars: fixes put back in teal and money spent in the accent colour, side by side, each on its own scale. Money's is on the left and fixes' on the right, each labelled in its bar's colour and ending on a round number with a round middle, so a slow day's fixes still show beside a cheap day's cost
- Pointing at a pair highlights it and shows a card beside it, on the side with more room: the date, the fixes and texts written, the kinds written, the money spent with the requests, the cost of each model and the tokens. The card is drawn over the chart and never takes the pointer
- The two figures at the top, money spent and fixes put back, each with a square in its bar's colour, stand for the chart's legend. Below the chart come By action, By app (the six with the most fixes) and By model
- Fixes are counted from the release that brings this, called 0.4.1 in the page's note and the documentation; the number has to match the release that ships it

## 2026-11-12 — The model list says what Handy's says, in a look of its own, and Your words is redrawn

The maintainer found the list of plain words too simple, with nothing that stands out and no languages or speed to see. They asked for every element of Handy's list, in a design with nothing in common with Handy's. They also found the row for adding their own words poor-looking.

- Read from Handy's source, its list has per model:
  - a mark for the one in use;
  - the name with a Live icon;
  - an accuracy grade for each of the person's languages;
  - a speed level and the size;
  - a status line while downloading or loading;
  - stop and delete;
  - a legend of the scales.
- OmanAI's rows carry each of these:
  - a tile in the colour of the model's family with its symbol (Apple's, Parakeet, Nemotron, Whisper);
  - the name with Live and "Best for your languages" tags and an ⓘ;
  - Speed and Accuracy as five steps with a word under them, such as "Very fast" or "Excellent", beside the download size;
  - the person's languages as chips, ticked or crossed, and a globe button with how many languages it knows;
  - a status line while downloading: "Downloading 45% of 609 MB, then in use", then "Preparing for this Mac's Neural Engine". When the model can't run, the line says why;
  - "In use", or Use or Download, a stop button while downloading, and a ⋯ menu with its details and Delete Download.
- A ? over the list explains every step of Speed and Accuracy, what Live means and where the languages come from.
- The ⓘ opens everything about the model: who made it, its speed and how soon its words show, its accuracy, whether it is live, how it picks the language, the size, the macOS it needs, its licence, and every language it knows, with the person's tinted.
- Handy grades accuracy for each language from its own benchmarks. OmanAI has no such figures, so it rates each model once, from 1 to 5, from published benchmarks and its own tests, and shows for each of the person's languages whether the model knows it. Speed is rated from how soon the words show, as measured for the live models. The ratings are `DictationModel.speed` and `DictationModel.accuracy`.
- The suggestion is the fastest live model that knows every one of the person's languages and can run here: Parakeet Unified, then Nemotron Unified, then Apple's.
- Your words:
  - a field across the row with an Add button;
  - the words as tokens, each with a button that takes it out;
  - a count, and an empty state with examples.
  Several can still be added at once, with commas between them.
- Capsules in Settings have circular ends. Drawn with continuous ends, a thin line stood off each end.

## 2026-11-12 — Dictated words wait in the pill when nothing can take them

The maintainer asked whether OmanAI could notice when a dictation finishes with nothing that takes text under the cursor, such as the desktop, a list or a web page with no field, offer to copy the words or let them click into a field, and then go. They said yes to the design below, and asked the assistant to decide the rest; the choices not named in it are the assistant's.

- Right before dictated words are pasted into another app, OmanAI asks Accessibility what has the cursor in the app in front and sorts the answer three ways: it takes text, it clearly doesn't, or it can't be told. Words that can go in, or can't be told, are pasted as before. The rules are in `TextFocusRules.swift`
- Takes text: a text field, text area, combo box or search field, by role or subrole; anything else whose value can be set, apart from controls such as sliders and checkboxes, which covers text views of an app's own making and pages made to be written in, such as a mail being composed; and anything not named below that has a text range. A terminal's text area takes a paste although its value can't be set
- Clearly doesn't: the Finder's desktop, lists, outlines, tables, column browsers, rows and cells, a web page with no field in focus, the app itself when none of its windows has the keyboard, and buttons and other controls. OmanAI's own windows in front count too
- Can't be told: everything else. That includes an app that answers that nothing has the cursor, which the design asked for counted as clearly not: read on this Mac, Slack and the other Electron apps answered exactly that, and dictations into them would have waited instead of going in. Terminals, remote desktops and virtual machines are never asked
- A text range alone doesn't make a field: the Finder's desktop has one, for finding icons as their names are typed
- A password field counts as can't be told. A dictation made while one has the cursor goes in as before, but words that wait never go into one, because a click into it is for typing a password and Return could follow the words
- When nothing can take them, the words stay in the pill, which says "Click where these words should go", with × and Copy where the seconds and Done were. Copy copies them and closes the pill, × throws them away, and Escape cancels as before. The transcript is kept as usual, as soon as the words are ready
- While they wait, the app in front is asked again four times a second. As soon as a field that takes text has the cursor, in the same app or another, the words are pasted there, with the space after them and Return or ⌘Return if Settings says so, and the pill fades. An app that can't be told is never pasted into this way, since nobody chose it
- After a minute with no choice, the words are copied and the pill says "No field was chosen, so your words were copied." for a moment
- Accessibility is asked away from the main thread, so an app slow to answer never holds up the pill or the menu bar. Each question has the 0.25-second limit that reading a selection has
- While words wait, the dictation itself is over: the menu bar icon is still again and opens the panel, and the shortcuts start a new dictation. Either first copies the waiting words, so none are lost. Opening the panel also closes the pill, which under the menu bar icon would hang where the panel does

## 2026-11-12 — Paste in the pill, for words that wait

The maintainer tried 0.4.2. Words dictated with the Finder in front waited in the pill, as they should, but a click into an Electron app's message field didn't take them, and they had to press Copy and paste by hand. Electron apps answer that nothing has the cursor even while their own field has it, so they can't be told, and by the entry above waiting words never go into them by themselves. The maintainer's first idea had been to ask for the cursor to be put in place and then paste, and they asked for that as a button.

- The waiting pill has Paste beside × and Copy. A click into a field, then Paste, puts the words where the cursor is, with the space after them and Return or ⌘Return if Settings says so, and the pill fades. The pill never takes the keyboard, so the field just clicked keeps it, in any app
- Paste doesn't ask what has the cursor first, because the person has just chosen the place. A paste that can't be made copies the words instead, as after a dictation
- Where an app says what has the cursor, a click into a field still takes the words by itself
- The pill says "Click in a field, then Paste". "Click where these words should go" left no room for a third button and didn't mention Paste
- Paste's symbol is the one macOS's Edit menu shows for Paste, beside Copy's

## 2026-11-12 — While words wait, Electron apps are asked to say what has the cursor

The maintainer asked for a click into a field to take waiting words in Slack and the other apps that can't say what has the cursor, as it does elsewhere. With their yes, a test switched on those apps' accessibility support through `AXManualAccessibility`, the switch Electron offers apps that assist the person, while they clicked into each app's field. Slack and two other Electron apps then named their message field within about three seconds, and Arc did too. Chrome and another Chromium browser refused the switch.

- This narrows "Accessibility mode is not forced on in Electron apps" (2026-11-10). It is switched on only while dictated words wait for a field, only in an app in front that can't say what has the cursor, and only where the switch reads as off, so support that a screen reader or another tool switched on is never touched
- When the wait ends, however it ends, it is switched back off in every app OmanAI switched it on in
- Each app is asked once per wait. Terminals, remote desktops and virtual machines are never asked, as before
- An app whose switch can't be read, such as Arc, is left alone, so OmanAI never switches off what something else switched on. Chromium browsers that refuse it keep Paste
- A dictation made while such an app is in front goes in as before; nothing is switched on for it

## 2026-11-12 — The Lab, keys held together, and a cleaner pill

The maintainer tried 0.4.2 and asked for:
- round buttons in the pill;
- no Settings button in the panel's header;
- a dictation shortcut of keys held together, such as Right ⌘ with Right ⌥;
- a cleaner background behind the Floating look's words;
- in place of Settings when OmanAI is opened, a Lab with a few numbers (transcripts, fixes, how their English goes) and their transcripts.

The Lab opens from a right-click on the menu bar icon, whose menu holds Open Lab, OmanAI Settings and Quit. The rest is the assistant's.

- **The panel's header** keeps only its pin. Settings opens from the menu bar icon's menu, from the style chips' Create a style, and from the setup screens. Check for Updates leaves that menu; Settings' General page has Check Now.
- **Keys on their own become a chord:** one or more Control, Option or Command keys, left or right, held together. Control joins Option and Command for this.
  - In the Shortcuts tab, Record Keys takes the keys held and keeps the most that were held at once when they are let go. Esc stops recording, and the keys already chosen don't start a dictation while it records.
  - A chord counts only while its keys and no others are held. Shift, Fn or any other key makes the press a shortcut until every key is let go.
  - A chord that grows into another chosen one, such as Right ⌥ then Right ⌘ when both chords are chosen, hands over to the larger one.
  - Shift stays out of chords, since holding it to type capitals would start dictations.
  - Settings saved by 0.4.2 with a single key load as a chord of that key.
- **Opening OmanAI while it runs shows the Lab.** Settings had appeared because macOS brings back the app's window when an app is opened again, and OmanAI keeps its Settings window after it closes.
- **The Lab** is a plain macOS window. It has:
  - four figures: dictations, with words and time spoken; fixes put back, of all texts written; changes per proofread this week, against last week; and money spent this month and in all;
  - the last two weeks, day by day, as dictations and fixes put back;
  - "Your writing": for the last eight weeks, how many places a proofread changed on average, and the share of proofreads that found nothing to change;
  - the transcripts, with search, Copy, Delete, Delete All and how many to keep. They moved from Settings, whose Dictation page now has Model, Look, Words and Sound.
- **How the person's English goes** is measured without keeping any words. Each proofread notes how many places it changed, as its own count in `writing_actions`, migration v5. Fewer changes over the weeks means fewer mistakes in what they write. It works for any language, so the Lab calls it "Your writing".
- **The pill's round controls**, Paste from 0.4.3 among them, get an even white ring at 22%. In the maintainer's screenshot, the cancel button measured 70 by 68 pixels: lit from above, the glass's sides read darker than its top and bottom, and the circle looks a little wide.
- **The Floating look's words** sit on a stronger blur that fades out well beyond them:
  - blur radius 28 points, up from 14;
  - darkening 24%, down from 34%;
  - the fade starts a third of the way out and eases in and out, where it used to start halfway;
  - the blurred area reaches 30 points past the words' sides and 16 above and below;
  - the text's shadow is lighter.

## 2026-11-12 — OmanAI's own window replaces the Lab

The maintainer saw the Lab on their screen and turned it down: its name, what it said and how it looked. A page in Settings' grouped style and a dark glass one, both of the same layout, were turned down too, and they asked for research. The assistant looked at Apple's Journal on the Mac, Wispr Flow, Typeless, Paste and Flighty's Passport, and drew three directions. The maintainer chose the grid of bold tiles, then sent the home screen of another dictation app and asked for its map of the year, as GitHub draws contributions, without that app's sidebar. The rest is the assistant's.

- **The name:** the window is called OmanAI, and the menu bar icon's menu says Open OmanAI. Nothing is called the Lab any more.
- **The page** is light, with tiles in OmanAI's own colours, teal into blue with violet. It is not Settings' grouped form: plain grey rows were what was turned down. It has a dark form too.
- **A stretch of time** is chosen at the top: This week, This month or All time. It sets every tile.
- **The first tile** says how many words were spoken in the stretch, with dictations, minutes, and pages or time saved under the number. The stretch is drawn as OmanAI's wave: a day at each step of a week or month, and a week or month at each step of all time.
- **Two small tiles:** the streak, with this week's days as dots, and the speed in words a minute against typing.
- **The second row has three tiles, chosen by what there is to say.** In order of choice: fixes, by kind; Your English; where the person dictates, by app; time saved; and, until a proofread has been counted, an invitation to proofread. They are shown in one steady order, and one of them is in colour. When time saved has no tile it is said under the first tile's number.
- **Tiles follow what was ever counted, not the stretch,** so they don't come and go with every quiet week. Someone who never dictated gets their fixes as the first tile, and someone new is told how to start.
- **The year map** has a square for each day of the last 53 weeks, darker for more, in four shades set by the busiest day shown. It counts words or fixes. Pointing at a square says its words, the time saved and the date. Days before anything was counted are only outlined, and the card says since when it counts.
- **What is measured and what is worked out:**
  - measured: words, dictations, time, speed, the streak, the apps and the fixes;
  - worked out: pages, at 275 words each; "times typing" and time saved, against typing at 40 words a minute, the usual figure for an adult. Both say so when pointed at.
  - Your English is the count each proofread keeps of the places it changed, from this version on.
- **Every dictation is counted without its words,** in a table of its own, `dictation_counts`, migration v6: when, how many words, how long, which app. The Lab counted the transcripts kept, so keeping the last 50, or none, made its numbers wrong. Deleting transcripts leaves the counts. The table is filled once from the transcripts already kept.
- **A day counts for the streak** when anything was dictated or written on it. Until today is over, yesterday's run still stands.
- **Transcripts** are listed day by day under the map. Copy shows under the pointer, a click shows all of a long one, and a right-click deletes. How many to keep and Delete All are in the menu that says how many are kept. Search is in the window's toolbar, beside a button for Settings.
- **Money is left out.** It has its own page in Settings.
- **An app's icon** is found by the app's name, among running apps first and then in the usual folders, since only the name is kept with a dictation.

## 2026-11-13 — After a first look at the window: the chip stays chosen, and the microphone shows

The maintainer tried the window for five minutes in a test build with their own dictations and liked it. They asked for: rows that don't jump when Copy shows; the line of the first tile to follow the pointer, as the year map does; and search over the transcripts instead of in the toolbar. They also reported that the panel keeps going back to their Slack template instead of the chip they chose last, that the panel's microphone can hardly be seen and could be a round button, and that the shadow behind the Floating look's words draws too much attention, for which they want variants to choose from. They said to release once this was done. The rest is the assistant's.

- **A row of transcripts keeps its height.** Copy and the app's icon lie over the row's corner. Laid out in the row, the taller Copy button made a row of one line 4 points taller under the pointer, and every row below it moved.
- **The first tile's line follows the pointer.** The step under the pointer gets a mark, a thin line down from it, and a note beside it: when it was, and its words with the time saved, or its fixes. Days still to come say so. The note goes to the right of the mark where there is room and to its left otherwise, and never past the tile.
- **Search is in the heading of the transcripts**, beside how many are kept, so that what is found shows right under what was typed. The toolbar keeps Settings alone. The field doesn't take the keyboard when the window opens.
- **The chip chosen in the panel stays chosen.** This supersedes "The template an app was last written in is remembered when it is used, not when it is chosen" of 2026-11-11.
  - A click on a chip is remembered for that app at once, whether or not anything is then written with it.
  - As written is a choice like any template. It used to be stored as nothing, so an app went back to the default template, or to whichever template was used there before. The table that holds the choices can now name no template, migration v7, `app_style_choices`.
  - Writing with the chip the panel opened on stores nothing. Only a choice is kept, so a default changed later in Settings still reaches every app nothing was chosen in.
  - A template's shortcut is one rewrite and not a choice. It used to leave its template chosen for the app. The maintainer has a shortcut for their Slack template, and the two apps remembered on their Mac were both on Slack, so this may be what put their panel back on it; which of these causes it was could not be told from the data.
  - An app nothing was chosen in still starts on the default from Settings, as Settings says, and not on the chip chosen last in another app.
  - A choice is kept under the app's bundle identifier, under its name where it has none, and under one key for no app at all.
- **The panel's microphone is a round button.** On its own beside Write it is glass with the even ring the pill's buttons have, as high as Write. At the end of a field it is a flat patch on the field's glass. Its symbol is filled and in the text's colour, where it was an outline in grey.
- **The shadow behind the Floating look's words is not decided.** 0.4.4 has the lighter one from the entry of 2026-11-12, which the maintainer had only seen in pictures. Variants are to be shown on their screen before one is chosen.

## 2026-11-13 — The Floating look darkens only what is bright

The maintainer asked for less of a shadow behind the Floating look's words, with variants to choose from. Away from home, they agreed to the variants being shown on their screen if it wasn't locked, and left the choice to the assistant. This supersedes "The shadow behind the Floating look's words is not decided" in the entry above. The measurements are in KNOWN_ISSUES.md.

- **Only what is bright behind the words is darkened.** Each colour goes through one curve: white comes out as 0.55, a mid grey of 0.5 as 0.44, and what is darker stays nearly as it was. The even darkening of 0.4.4, by 0.24 everywhere, is gone.
- **The curve is Core Animation's `curves` filter, in a layer of its own under the blur.** `luminanceCurveMap` bends brightness the same way but on brightness alone, and turned the desktop picture's colours grey behind the words. As a second filter on the blur's own layer, the curve needed that layer faded as a whole, which weakened the blur.
- **White goes to 0.55, not 0.45.** 0.45 made white words easier to read over a white window, 4.4:1 against 3.4:1, but darkened every background more, which is what the maintainer wanted less of. 0.55 keeps white words above 3:1 over white.
- **The curve keeps its full strength out to 45% of the way to the oval's edge,** where the blur keeps it out to a third, and then fades out the same smooth way. So the words' longest lines stay over the darkened part.
- **The blur stays at 28 points, and the letters' shadow goes from 0.3 to 0.35,** which helps where the background is now lighter.
- **What changes, behind the words, from 0.4.4 to 0.4.5:**
  - over the desktop picture, brightness 0.48 to 0.53 and white words 4.2:1 to 3.6:1, so less of a dark cloud;
  - over a white window, 0.67 to 0.55 and 2.3:1 to 3.4:1, so the words can be read: here it is darker than before, on purpose;
  - over a dark window, 0.17 to 0.20 and 14.2:1 to 12.8:1, so less is darkened where nothing needed it.
- **Where a macOS lacks the filter,** the even darkening of 0.4.4 stands in.
- **The numbers sit together in `FloatingBackdrop`,** read from the environment, so variants can be drawn side by side with the same code as the app.

## 2026-11-13 — The website shows 0.4.5

The maintainer asked for the website to be updated and its recordings filmed again. The rest is the assistant's.

- **Dictation gets a clip in the header,** a fifth after Compose: words appear in the pill under the menu bar icon, then go into the chat drawn under it. It also gets a fifth use case, ✨ and a rewrite in the Work style, and a section of its own with pictures of the Card and Floating looks.
- **OmanAI's window gets a section** after dictation, with one picture of it and three short lists: words and time, what the writing needed, and transcripts. The picture shows made-up use, never the maintainer's.
- **Every recording and panel picture is filmed again,** so the panel on the site is the one people install: without the gear, with the chip memory and the round microphone of 0.4.4.
- **The docs follow 0.4.5:** a section for OmanAI's window, keys held together, words that wait for a field, Settings opened from the menu bar icon or the window, and transcripts kept in the window.
- **Old recordings and pictures are deleted** once nothing names them, and new ones get new names, because Cloudflare keeps a file for a week.

## 2026-11-14 — OmanAI is installed from a disk image

The maintainer asked for an installer like other Mac apps have, a direct download link on the website, and both kept up to date. The rest is the assistant's.

- **A disk image, not an installer package.** It holds OmanAI beside a link to Applications, over a picture that says "Drag OmanAI to Applications" with an arrow from one to the other. That is how Mac apps are usually installed, and it needs no administrator password and leaves nothing behind.
- **The picture is OmanAI's own,** light, with the website's soft teal, blue and violet, and drawn at 1x and 2x. Finder's path and status bars, which some people keep on, cover its bottom 60 points, so nothing there matters.
- **Every release makes one.** `release.sh` puts the stapled app into the image, then signs, notarizes and staples the image itself, so Gatekeeper accepts it before it is opened. The release carries it as `OmanAI-x.y.z.dmg` and as `OmanAI.dmg`.
- **One address for the website:** `releases/latest/download/OmanAI.dmg`, which GitHub always sends to the newest release's `OmanAI.dmg`. The site never needs a new link, and its script shows the version and size it gets from GitHub.
- **Updates keep using the zip.** The feed is made from a folder without the image in it, so Sparkle never offers the disk image.
- **dmgbuild lays out the window** by writing the `.DS_Store` itself, where scripting Finder needs a window on the screen and is known to be unreliable on GitHub's machines. It and its two helpers are pinned by version and hash, and installed into a throwaway folder for each build.

## 2026-11-13 — Quick fix: Proofread puts its corrections straight back

The second build in the research report on competitors: an option on a global shortcut that proofreads the selection and pastes the corrected text back over it without opening the panel, as Tidy, Raycast, Kerlig's headless mode and Fluent do. The maintainer asked for it to be built and for the choices to be made and recorded here.

- **An option on Proofread's shortcut.** The Shortcuts tab has a Quick fix switch right under "Proofread selection", off at first. With it on, that shortcut corrects the selection where it is and opens no panel. The panel's own Proofread button and every other shortcut are unchanged. With the panel open and holding the keyboard, the shortcut proofreads in the panel as before, as a dictation goes into the panel's field then.
- **Proofread only.** Templates' shortcuts don't get it, nor do Rewrite and Explain. A template's shortcut is a rewrite, and a rewrite changes the wording, while the people the report quotes accept a silent replace only for small edits. Explain is never pasted, and Compose has nothing to replace.
- **The template of the app still counts.** The proofread follows the template the app's panel would open on, the chip chosen there or the default from Settings, so a template's habits with capital letters, apostrophes and full stops hold as they do in the panel.
- **The same proofread as the panel's:** the same request, model and quality. A cut-off answer is never pasted, and the answer is cleaned as the panel cleans it before anything is pasted.
- **Pasted the way Replace pastes.** The selection is read again just before, and nothing is pasted if it changed. The paste is a ⌘V, so ⌘Z in the app brings back what was there, and the clipboard is given back afterwards.
- **Nothing is pasted when:**
  - nothing is selected: the alert sound plays, the icon shows an exclamation mark for 2 seconds, and nothing is asked of the model;
  - the proofread found nothing to correct, counted as the panel counts changes, so the text keeps any formatting a plain paste would drop;
  - the selection changed while it worked, or another app is in front by then, which isn't brought back to the front;
  - the proofread changed more than half of the words of a text of 16 words or more, the measure at which the panel shows the original instead of marks. A proofread shouldn't do that, so it waits for a look;
  - the app is a terminal, where the panel asks for a second press before a paste;
  - the request failed, or the key or the Accessibility permission is missing.
- **The menu bar icon:**
  - while it works, the wave rocks steadily from side to side, unlike a dictation's, which follows the voice. With Reduce Motion it stays still and faint;
  - done shows a check mark for 3 seconds;
  - nothing pasted shows an exclamation mark in a triangle. It stays until the icon is clicked, the panel opens, or another quick fix or a dictation starts, so a failure isn't missed;
  - VoiceOver reads the icon's state, and says how each quick fix ended.
- **One thing at a time.**
  - A second press while one works does nothing.
  - A click on the icon while it works stops it before anything is pasted, and opens the panel on the same text with Proofread running there.
  - Opening the panel any other way, or starting a dictation, stops it too, since its paste must not land in the panel. A paste already under way finishes.
  - During a dictation the shortcut only plays the alert sound. Words waiting for a field are copied first, as when the panel opens.
- **The last quick fix in the panel.** A click on the icon while its check mark or exclamation mark shows, or Show Last Quick Fix in the icon's right-click menu, opens the panel on it. It is the Proofread result screen, with the changes marked as Settings says and a line saying what became of it:
  - one that went in, or found nothing to correct, is only for reading. It has Copy, and no Replace, Try again or change, since its text is in the app already. The line says that ⌘Z in the app brings back what the person wrote;
  - one that wasn't pasted has Replace, which puts it in once the same text is selected again, and Try again and a change as after any proofread;
  - one that failed shows its error, with Try again.
  The panel itself gets no new row: the menu bar icon is where a quick fix shows, so it is where the way back to it starts.
- **Kept in memory only,** until OmanAI quits or the next quick fix ends, and never stored. Spending and OmanAI's window count it as they count a proofread from the panel: a text written, and a fix put back when it was pasted.
- **A missing key or permission keeps nothing,** so a click on the icon opens the panel, whose setup says what is missing.

## 2026-11-13 — The person's own actions, saved in Settings

Built for the next version from item 3 of the research report on competitors: instructions such as "Make it shorter" or "Turn into bullet points", written once and run on the selection from the panel or from a shortcut, as saved versions of the panel's Describe your change. The maintainer wants feature choices made and written down here, so the ones below are the assistant's.

- **What an action has:** a name, an instruction, and what becomes of its result: Replace or Insert, as with Rewrite, or only to read, as with Explain. It can have a global shortcut. None come with OmanAI: the list is the person's own, so the panel holds nothing they didn't choose.
- **Where they are kept:** a `custom_actions` table, migration v8, in the order they were made. An action's shortcut is kept with the other shortcuts in the preferences, under `custom:` and the action's identifier, as a template's is under `style:`. A result kind a newer OmanAI wrote, which this version can't name, is read as only to read, so nothing is ever pasted that the version can't account for.
- **Settings has an Actions tab**, between Styles and Shortcuts. Actions are listed as styles are, each with Edit…, and Add an Action… makes one called New action. The sheet has the name, the instruction in a box of its own, Result as two choices with a line saying what each does, and the shortcut. Every change is saved as it is made. Delete Action… asks first in macOS's own alert, with Cancel as the button Return presses, and the shortcut goes with the action. The shortcuts are also listed in the Shortcuts tab, after the templates'. Drawn off the screen, the eight tabs fit the 600-point toolbar, between 40 and 560 points.
- **In the panel, the actions sit on one line in a tile of their own, right under Proofread, Rewrite and Explain**, in the order they were made. The three buttons keep their size and place however many actions there are. The line scrolls sideways under a fade at its right end, as the templates' line does, and the tile shows only when there is an action to run. A chip has a sparkle, the panel's mark for an instruction, or reading glasses when the answer is only read, and its instruction shows under the pointer. The tile adds 64 points to the panel's height.
  - Not chosen: inside the row of Proofread, Rewrite and Explain, which would squeeze them; above them, under Describe your change, which would move them down for everyone with an action; a menu behind a button, which hides the actions behind a click; and the tile of template and context chips, where a chip only chooses and starts nothing.
- **An action whose result is pasted is sent as the rewrite that typing its instruction into Describe your change sends**, word for word: the chosen template, the context that is switched on and the standing preferences apply. Its result has Replace or Insert, Copy, Try again and Make a change, as Rewrite's has, and a result written from dictated words goes in with Insert.
- **An action whose answer is only read has rules of its own**, written like Explain's: the answer is for the person, shown in the panel, never pasted. It takes the context and the screenshot, but neither the template nor the standing preferences, since it is not written as the person. It answers in the language of the instruction unless the instruction asks for another, in plain text. Its result has Copy and Try again, and Try again asks afresh, as Explain's does.
- **An action without an instruction is left out of the panel**, its shortcut does nothing, and Settings says so under its name. An action needs a selection, as Rewrite does: with nothing selected its shortcut opens the panel in Compose and runs nothing.
- **Counting:** a text an action wrote is noted as "Your actions", a kind of its own on the Spending page, whatever its result. One that is put back is a fix, and OmanAI's window counts it among the rewritten ones.
- Apple's on-device model gets the same split in plain sentences: an action whose result is pasted is its rewrite with the instruction, and one to read asks for an answer for the person, with no template.
- `LiveWritingTests` has four cases for actions: bullet points to paste, a summary to read, an answer in the language of the instruction, and text that gives orders. They have not been run, because they need a key.

## 2026-11-14 — A new app icon: the menu bar's wave on blue

The maintainer asked for the app icon to match the menu bar icon, one white wave on a blue rounded square, and sent a picture of a white wave on slate blue. This supersedes "App icon: the `flow` concept" of 2026-11-10. The rest is the assistant's.

- **The wave is the menu bar icon's own curve.** `wave.svg` holds the path from `MenuBarIcon.svg` unchanged, 41 times larger and centred on its middle point, so the two icons are one shape. Its line is 2.4 where the menu bar's is 2, a fifth heavier, so that it still reads at 16 pixels. It spans about 64% of the icon's width.
- **The blue** runs from #5b7eac at the top to #36537c at the bottom: the slate blue of the maintainer's picture, about #4d6f9c to #3f5f8a, with a little more light and depth. As macOS draws it, the middle of the icon comes out at #476692, the middle of that range.
- **One group holds the wave, with glass and specular light on and a light shadow**, the way Icon Composer builds Apple's own icons. The line and lens layers of the old icon are deleted. Its sources stay in `design/icon/` with the other concepts.
- **The file asks for the blue to run from the top left to the bottom right, but macOS draws it from top to bottom.** Nothing in macOS 27 follows the direction of an icon's background gradient (see KNOWN_ISSUES.md). So the top is lighter and the bottom deeper, and the glass's highlight runs along the top.
- **One file serves macOS and iOS** (`"squares": "shared"`), so the iPhone app can use it as it is. It compiles for iPhone and iPad without a warning, and the Dark, Clear and Tinted looks work on both. In Dark the wave takes the blue, on black.
- **The website and the README show the same icon:** the favicon, which is also the README's picture, and the logo beside the name at the top of both pages. The favicon adds a soft light along its top edge and a shadow under the wave, as the app's glass has. The pages ask for `favicon.svg?v=2`, so neither Cloudflare nor a browser keeps showing the old one.
- **The picture shown when the site is shared is `og-2.png`:** the same layout, words and cards as before, with the new icon on blue instead of the old green. It has a new name because Cloudflare keeps a file for a week, and `og.png` is deleted, since nothing names it any more.

## 2026-11-14 — OmanAI on the iPhone

The maintainer asked for an iPhone version that does everything OmanAI does now, opened, dictated into and proofread from, with a design like the Mac's and as easy to use. The choices below are the assistant's.

- **One package for both.** The iPhone app is a second target in `project.yml`, `OmanMobile`, built from the same `OmanKit` as the Mac app. It reuses the panel's, dictation's, the window's and Settings' view models whole, so a change to how a proofread or a dictation works reaches both. What only a Mac has is behind `#if os(macOS)`: the status item, the floating panel, global shortcuts, keys held on their own, the pill, Accessibility, the picture of the screen, opening at login and Sparkle.
- **iOS 26 and later,** for Liquid Glass, which the Mac panel's look follows, for SwiftUI's new tabs, and for Apple's on-device model and SpeechAnalyzer, which need it anyway.
- **The same bundle identifier as the Mac app,** `com.romanbitca.oman`, so both are one app to Apple and can share one iCloud container.
- **Four tabs.**
  - **Write** is the Mac panel's own screens, with a box on top in place of the selection, since iOS lets no app read or change another app's text. The box takes typed, pasted or dictated text. A result's main button is **Use**, which puts it back in the box for the next step, and Copy takes it away.
  - **Dictate** has one large microphone button. The words show as they are said, as in the pill, and are copied when the dictation ends. Proofread and Rewrite open Write on them.
  - **Home** is OmanAI's window: the counts, the map and the transcripts.
  - **Settings** is the phone's own grouped list, with the Mac's choices except the ones only a Mac has.
- **The look:** the panel's glass tiles over a soft teal, blue and violet background, the Mac's glass buttons and chips, and the system's tab bar, which iOS 26 draws as glass.
- **What the system bridge does on the phone:** writing into another app becomes copying, the Accessibility permission counts as given since there is none to ask for, the microphone is asked for through `AVAudioApplication`, and the start and end of a dictation play the system's own sounds.
- **Not built, and the next steps for getting text in and out without copy and paste:** a share extension, a keyboard, Shortcuts actions, a widget or a control in Control Center.
- **Not in the App Store.** It is run from Xcode, signed with the person's own team from `mac/Signing.xcconfig`, which git ignores (see docs/IPHONE.md). The simulator needs no signing.

## 2026-11-14 — Syncing through iCloud

The maintainer asked that the person may, or may not, connect their Apple Account and sync everything through iCloud. The choices below are the assistant's.

- **Off until the person turns it on,** with a switch on each device: in Settings, General on the Mac, and in Settings on the iPhone.
- **What syncs:** the styles, the actions, and the settings that belong to the person: Quality, the language to answer in, the instructions, the default style, whether each app remembers its style, how Proofread shows its changes, the dictation words and whether filler words are taken out.
- **What doesn't:**
  - The API key stays in each device's Keychain. It is a secret, and sharing it through iCloud Keychain would need the Mac app and the iPhone app in one keychain group, which a Developer ID app only gets with a provisioning profile.
  - Transcripts and counts stay on each device, in this version. They are the largest data and the most private, and the window counts what was done on that device.
  - What belongs to the device stays there: the writing model, since Apple's model runs on some devices and not others, the dictation model and its language, the theme, the panel, shortcuts, the pill, the microphone, sounds, and the style last chosen in each app.
- **How:** Apple's CloudKit sync engine, `CKSyncEngine`, in a zone of its own, `OmanAI`, in the private database of the person's iCloud, in a new package target, `OmanSync`. Each style and each action is a record, and the settings are one. What the person wrote is in CloudKit's encrypted fields; only the dates of changes are plain.
- **When both changed, the newer change wins.** A style or an action is taken whole. Settings are weighed one field at a time, so a change to one on the iPhone doesn't undo a change to another on the Mac. At the same date, iCloud's wins, so the second device takes on what the first sent.
- **A setting changed before anything was noted beats one still at its default.** Without this, a new iPhone turning syncing on after the Mac would have nothing to tell its defaults from the Mac's choices, and could undo them.
- **A deletion is followed, unless the other device changed the style or action since;** then the change brings it back. Deletions made while syncing was off are sent when it is turned on.
- **Each change and its date are noted in `sync.json`, beside the database,** whether syncing is on or not, by stores that stand in front of the database's. The database is unchanged. The same file keeps the sync engine's state and the parts of each record iCloud needs.
- **Changes are fetched** when OmanAI starts, when it comes to the front, and every five minutes while it runs. On the iPhone, iCloud can also tell the app, which has the remote notification background mode.
- **Signing out of iCloud keeps everything on the device** and forgets what was learnt from that account. Another account signing in gets everything sent again. When OmanAI's data is deleted from iCloud, syncing stops on each device rather than sending it all back.
- **Only builds signed for the container can sync.** CloudKit stops an app that asks for a container it isn't entitled to, so the container's name comes from the build setting `OMAN_ICLOUD_CONTAINER` through the Info.plist, and is empty unless set. Without it there is no switch and CloudKit is never touched. The iPhone app sets it from `Signing.xcconfig`. The Mac's Developer ID build needs a provisioning profile with iCloud, which only the maintainer can make (see docs/ICLOUD.md), so releases don't sync yet.
