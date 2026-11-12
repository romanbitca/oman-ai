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

