# Session Log

Date-stamped log of what each work session accomplished.

---

## 2026-11-11 — Backdrop removed

- The maintainer installed 0.3.1 and sent screenshots with the panel open and closed: the backdrop grayed out half the screen without blurring it, and clear glass showed the app's text through the tiles. It looked very bad
- Removed the backdrop window and clear glass. Tiles are frosted glass again; the dark panel with white text, interactive glass buttons and white "on" chips stay
- Verified: 305 tests pass and the app builds. Not verified: how it looks on screen
- Published 0.3.2 from a tag on `main`, with the release's test step standing in for the pull request's check again. All three release jobs passed; the command waiting on them lost its connection to GitHub, which looked like a failure until the run was read. Checked from outside: Gatekeeper accepts it as notarized Developer ID, it is version 0.3.2 (3002), and the zip's and the feed's signatures verify with the update key inside the installed app. The maintainer's Mac had already updated itself to 0.3.2

## 2026-11-11 — Control Center look for the panel

- The maintainer compared the panel with Control Center and asked for the native look, including Apple's glass buttons that flex when pressed
- Added a click-through backdrop window that dims and slightly blurs the side of the screen behind the panel and fades out beyond it, hidden while the panel is pinned. The panel is dark with white text when the theme is Match system, its tiles are clear glass over the backdrop, its buttons use interactive glass, and chosen chips are white instead of purple. Settings is unchanged
- The rules for which glass a shape gets and where the backdrop goes are plain code with tests. 310 tests pass and the app builds without warnings
- Not verified: how any of it looks, because glass and behind-window blur don't render offscreen; that clicks still land on clear glass, which has the 2% fill as a precaution; and how strong the dim and blur feel. The maintainer reviews it on screen
- Published 0.3.1, with this and the Writing Tools fix, from a tag on `main`. The pull request's own check was still running when `main` moved, so the release's test step stood in for it, and all three release jobs passed. Checked from outside: Gatekeeper accepts it as notarized Developer ID, it is version 0.3.1 (3001), the zip's and the feed's signatures verify with the update key inside the installed 0.3.0, and the public feed serves 0.3.1

## 2026-11-11 — Back covered by Apple's Writing Tools

- The maintainer tried 0.3.0: Explain worked against the live API, but Back sometimes did nothing and the app sometimes felt slow
- Read the system log of the installed app instead of driving the screen. No hang or unresponsive report. Apple's Writing Tools set up its floating button and host window inside OmanAI's panel seconds before the failed Back, and it had done so in 0.2.1 too
- Turned Writing Tools off for OmanAI's own text in the panel and Settings. A new test checks that the panel's text views and a one-line field's editor report it off; the field's editor reported "limited" before
- Back now writes the screen it went to in the system log, without any text
- Verified: 302 tests pass and the app builds. Not verified: Back on screen after the change, and the cause of the slowness

## 2026-11-11 — Explain, smaller buttons and spending

- Added Explain to the panel: it reads the selected text as its recipient would and says what they will understand, how it sounds and what could be misread. It uses the conversation's context, has its own short system prompt and an assignable shortcut, and its result can be copied but never pasted
- Proofread, Rewrite and Explain are now one row of 40-point capsule buttons instead of two 80-point cards
- Added a Spending page to Settings with totals for today and this week and bar charts for the last 14 days and 8 weeks. Each Claude request now records its token counts in a new `api_usage` table, priced with Anthropic's list prices from 2026-11-11. No text is stored
- Verified: 301 tests pass, 30 of them new, and the app builds. Token counts are read separately from the stop reason, so a change in how Anthropic reports usage can't make answers look cut off. Offscreen renders checked the button row, the explanation screen and the Spending page in light and dark, with real charts. Glass doesn't render offscreen, so the buttons' shapes were measured instead: the widest label needs 104 of its 115 points
- Not verified: Explain against the live API, which needs a few real requests with the maintainer's key, and the new buttons as glass on screen. The costs are checked against hand-worked figures, not against a real Anthropic bill
- Removed this session's leftover build copies from LaunchServices. Only `/Applications/OmanAI.app` and an older copy in the Trash are still registered
- Published 0.3.0 from a tag on `main`, after CI passed on pull request #7. All three release jobs passed. Checked from outside: Gatekeeper accepts it as notarized Developer ID with the ticket stapled, Sparkle's helpers are signed by the same team, it is version 0.3.0 (3000), the zip's and the feed's signatures both verify with the update key inside the installed 0.2.1, and the public feed address serves 0.3.0. Not checked: the update itself on the maintainer's Mac

## 2026-11-11 — Security review and fixes

- Reviewed what leaves the Mac, the clipboard handling, the API key, prompt injection, the two permissions, Sparkle updates, the release pipeline and the repository's history, then fixed what the review found. The choices made are in DECISIONS.md
- Panel and API: prompt tags that selected or pasted text can't forge, cut-off responses no longer accepted as finished, hidden context no longer sent unseen, an uncropped screenshot preview, requests that wait for the screen capture, results cleaned of hidden characters, the clipboard read only on request, and smaller fixes
- Clipboard and paste: `ClipboardRoute` gives the clipboard back when the app has read the paste and undoes a copy that arrives late. No synthetic ⌘C for terminals, remote desktops and virtual machines. Insert checks where the cursor is, and terminals need a second press
- Releases: the workflow is split into check, build and publish, with secrets in an approved `release` environment. Sparkle now requires a signed feed and checks an update before unpacking it. GRDB, Sparkle and XcodeGen are pinned. docs/RELEASING.md describes the new setup
- Verified: 266 tests pass, and passed 20 runs in a row, half of them with every CPU core busy. The app builds. A throwaway Release build and a throwaway key showed that the feed tool signs the feed once the app asks for it, and both signatures checked out independently. Lazy pasteboard delivery was checked between two processes on a private pasteboard
- Not verified: capture and paste in real apps with the new clipboard code, which needs an on-screen test. The new prompt format against the live API, which needs a few real rewrites. The workflows and `setup-release-secrets.sh`, which have not run since they changed. A real update from 0.2.0
- A second review of the merged changes found ten more points. Fixed: overlapping clipboard operations, a black flag emoji that could hide text, a saved key that macOS won't hand over being reported as missing, a fragile check in the setup script, and two duplicated helpers. `Package.resolved` turned out to be rewritten by Xcode as well as by `swift test`, so it is no longer committed. 271 tests pass
- Added the tag and `main` rulesets on GitHub, and a landing page in `site/` with a demo of the panel that visitors can try. Checked at desktop and phone widths in light and dark. It is not hosted anywhere yet
- Published 0.2.1 from a tag on `main`, with everything above. It was the first run of the reworked release workflow, and all three jobs passed: the tests, a notarized build, and a release with a signed feed. Checked from outside: the feed's signature is valid for the update key inside an installed 0.2.0, the feed's length matches the zip on GitHub, the address the app asks serves that feed, and the build log shows the same update key going into 0.2.1. Not checked: the zip's own signature, which the app checks itself when it updates. The run asked for no approval, see KNOWN_ISSUES.md
- The maintainer updated an installed 0.2.0 to 0.2.1 from inside the app, the first real update through Sparkle. Read from the installed copy afterwards: version 0.2.1 (2001), the same Developer ID team, a valid signature with the notarization ticket stapled, both new update checks on, and the same update key. The app only installs a zip whose signature it has checked, so the zip's signature is settled too
- The maintainer then tried 0.2.1 and reported that everything seems to work, which covers the Accessibility permission carrying over. With that, every acceptance point of W7 is met, and PLAN.md marks it done. W1 to W6 stay in progress until the maintainer signs off on their acceptance lists
- Next for the maintainer: choose where to host the landing page, and run `mac/scripts/setup-release-secrets.sh` so that a release asks for approval (see KNOWN_ISSUES.md)

## 2026-11-10 — Pivot to a menu bar writing tool, native Swift build

- Direction changed: writing tool first, meeting recorder parked. Decisions recorded in DECISIONS.md, phases W1 to W5 added to PLAN.md, CLAUDE.md and README.md updated
- Built in `mac/`: `OmanKit` package (OmanCore contract, ClaudeAPI, OmanStorage, SystemBridge, OmanUI) and the app shell (status item, non-activating panel, Settings window). The four modules were built in parallel by subagents against one shared contract, then reviewed and merged
- Haiku 5.5 is the default model, with Sonnet 5.5 and Opus 5.5 in Settings. Actions are Proofread, Rewrite, styles, free-text instruction and Compose
- Verified: 145 tests pass; the signed app builds and runs at a 28 MB footprint; scripted clicks on the icon open and close the panel under it while the frontmost app stays frontmost; every screen and both Settings tabs were checked in offscreen renders
- Not verified yet, because it needs the user's Accessibility grant and API key: selection capture and paste in real apps, typing in the panel, a live Claude request, real mouse clicks on the icon. W1 to W5 stay [IN PROGRESS] until those pass
- Fixed after the user's first try: Cmd+V did nothing in text fields, because a menu-bar-only app has no Edit menu. Added one for the Settings window, and direct handling of editing shortcuts in the non-activating panel, including non-Latin keyboard layouts
- oman did not appear in the Accessibility list because the build ran from a temporary folder. Installed a signed Release build to `/Applications/oman.app`
- Liquid Glass pass: the panel is now floating glass tiles in a fixed transparent window so shapes can morph, and Settings moved to a sidebar. Minimum OS stays macOS 14 with a material fallback. Layout checked offscreen and 145 tests pass, but real glass rendering has not been seen, because this session has no Screen Recording permission. The user is taking the design to Claude Design
- Signing: no Developer ID certificate on this Mac. The only paid team in Xcode belonged to a different account, and Xcode's login for it was rejected. The user needs to confirm which account signs
- The user likes the panel's look. Fixed a freeze: the main thread spun at 100% inside AppKit's Password AutoFill heuristics, which also made buttons look dead. Could not reproduce it on demand, so the fix (AutoFill heuristics off, confirmed idle afterwards) still needs real use to confirm
- Added assignable shortcuts (global, per style, and for results), redesigned Settings with new options (theme, quality, language, standing rules, default style, panel defaults), a pinned panel as a draggable floating window, and Apple's on-device model. 194 tests pass; the on-device model ran for real on this Mac. Real key presses for global shortcuts, dragging, and the look of the new Settings are not verified by me
- Second design pass from the user's feedback: curved drag grip at the panel's top-right corner, an opaque draggable Settings window, no bouncing motion. Installed the flow icon and menu bar glyph
- Signing: Developer ID works with the personal Apple Developer account (team S72639F3BR). Added `mac/scripts/release.sh` for sign and notarize
- First notarized build: Gatekeeper reports `Notarized Developer ID`, the ticket is stapled, and it is installed in `/Applications`. The signature changed, so Accessibility has to be allowed again. Selection reading and paste have not been re-tested on this build
- The app is now named OmanAI. The bundle ID, Keychain service and database folder did not change, so saved styles and the API key carry over
- Third design pass: the pinned panel's grip is a dark curve with a thin glass border, and Settings has no animation at all, including a hand-drawn switch. The first curved grip could not drag for two reasons, both found with real mouse events: shapes above the drag area took the click, and Liquid Glass in a custom shape counts as clear to the window server. Real drags moved the installed panel from the middle and both ends of the curve. The final build only removed an extra grab area that did not catch clicks
- Accessibility has been refused since the move from the Apple Development build to Developer ID, because the existing grant is tied to the old signature. It needs the user to remove OmanAI from the list and allow it again. Selection reading and paste still need re-testing on the Developer ID build, and the new Settings has been checked offscreen only
- Prepared the project for open source and automatic updates: MIT license, public README and contributor files, GitHub Actions for tests and for signed releases from a tag, Sparkle updates from GitHub Releases, an ad hoc default build, and the meeting recorder moved to an archive branch
- Published the repo and released `v0.2.0` through GitHub Actions. Verified: 200 tests pass locally and on GitHub, an ad hoc build works with no Apple account, the published app passes Gatekeeper as notarized Developer ID with Sparkle's helpers signed, and the feed's signature matches the key built into the app. Not verified: no installed app has updated itself yet, because 0.1.0 has no updater and the first real test needs a later release
- Next: a test and security review, the bug pass, and the landing page

## 2026-04-28 — Project bootstrap

- Repo created at github.com/romanbitca/oman-ai
- Created README.md, CLAUDE.md, PLAN.md, DECISIONS.md, KNOWN_ISSUES.md, SESSION_LOG.md
- Stack and v1 scope locked
- Next: run Phase 1 (Skeleton) with Claude Code

## 2026-04-29 — P2 verified by user

- Confirmed on user's Mac: app launches, `personal.db` auto-created at correct path, workspace switcher works, creating new workspaces produces new `.db` files, all schema tables present, settings seeded correctly, typecheck and lint pass, no console errors
- P2 closed. Next: P3 — Mac audio recording

## 2026-04-28 — P2 SQLite + workspaces implemented

- `better-sqlite3` 11.5 + `@types/better-sqlite3` installed; native module rebuilt for Electron 33's arm64 ABI via `electron-builder install-app-deps` (added as `postinstall` script so future installs stay correct)
- Workspace files at `~/Library/Application Support/oman/workspaces/{slug}.db` (Mac) — uses `app.getPath('userData')`; same code maps to `%APPDATA%/oman/workspaces/{slug}.db` on Windows
- `electron/services/migrations.ts`: schema-V1 SQL block (all 7 tables incl. `meetings_fts` FTS5), `applyMigrations` keyed by `PRAGMA user_version` and wrapped per-step in a transaction; `seedSettings` writes the three seed rows with `INSERT OR IGNORE`
- `electron/services/workspace-manager.ts`: `listWorkspaces`, `getCurrentWorkspace`, `switchWorkspace`, `createWorkspace`, `deleteWorkspace`, `initWorkspaces`, `closeCurrent`. WAL journal mode enabled. `slugify()` normalises display name to filesystem-safe slug
- `electron/ipc.ts`: four `ipcMain.handle` channels (`workspace:list|current|create|switch`); create auto-switches
- `electron/preload.ts`: exposes typed `omanApi.workspaces.{list,current,create,switch}` via `contextBridge`
- `electron/main.ts`: `initWorkspaces()` + `registerIpc()` on `app.whenReady`; `closeCurrent()` on `before-quit`
- `shared/types.ts`: `WorkspaceMeta`, `OmanApi`, and `Window.omanApi` global declaration
- `src/store/workspace-store.ts`: Zustand store with `current`, `workspaces`, `ready`, `load`, `switchTo`, `create`
- `src/components/workspace-switcher.tsx`: top-left dropdown button — shows current slug, lists all workspaces, inline "+ New workspace" form (Enter to submit, Escape to cancel, click-outside to close); displays IPC errors inline
- `src/App.tsx`: header bar with switcher; "oman" remains in main panel
- Verified end-to-end: clean userData dir → `npm run dev` auto-creates `personal.db`; sqlite3 confirms 7 spec tables + FTS5 internals + seeded settings (`transcription_mode=local`, `anthropic_api_key=NULL`, `drive_upload=false`) + `user_version=1`. An env-gated routine in main.ts (added then reverted) exercised create/switch/switch-back; user separately drove the UI to create a `t` workspace, confirming the full renderer→IPC→manager path
- `npm run typecheck`, `npm run lint`, `npm run build`, `npm run dev` all clean
- Next: P3 — Mac audio recording

## 2026-04-28 — P1 Skeleton implemented

- electron-vite + electron-builder wired up; main in `electron/`, preload at `electron/preload.ts`, renderer in `src/`
- TypeScript strict mode, project references (`tsconfig.node.json` for main/preload, `tsconfig.web.json` for renderer)
- Path aliases configured in both tsconfig and electron.vite.config.ts: `@/` → `src/`, `@shared/` → `shared/`, `@electron/` → `electron/`
- Tailwind 3 with `darkMode: 'class'`; `class="dark"` set on `<html>` so dark is the default theme
- shadcn/ui initialized via `components.json` (neutral base, CSS variables); `cn` helper at `src/lib/utils.ts`; full neutral color tokens in `src/globals.css`. No components added yet (none needed for P1)
- Zustand installed but unused yet; reserved for P2
- Scripts: `dev`, `build`, `dist:mac`, `dist:win`, `typecheck`, `lint`, `format`
- `electron-builder.yml`: dmg (arm64+x64) + nsis (x64), GitHub publish target, `mac.identity: null` for unsigned local dist (P12 will revisit)
- System tray with placeholder 22×22 PNG (`resources/tray-icon.png`); macOS template-image flag for menu-bar dark/light auto-invert. Click toggles main window; right-click shows Show/Hide + Quit
- Main window 1200×800, min 900×600, dark backgroundColor, autoHideMenuBar
- Empty React app shows "oman" centered (`src/App.tsx`)
- ESLint 8 + Prettier; rules forbid `any`, ignore underscore-prefixed unused vars
- Verified: `npm run typecheck` passes, `npm run lint` passes, `npm run build` produces `out/{main,preload,renderer}` cleanly, `npm run dev` launches Electron and main window with no console errors
- Gotcha discovered: `sandbox: true` + ESM preload fails silently. Documented in KNOWN_ISSUES.md; using `sandbox: false` for now
- P1 verified working on user's Mac: window opens, tray icon renders and toggles the window, no console errors
- 7 implementation decisions formalized in DECISIONS.md (sandbox flag, app ID, mac identity, tailwind/eslint versions, tray template image, window-close behavior, external link handling)
- Next: P2 — SQLite + workspaces
