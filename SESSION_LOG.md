# Session Log

Date-stamped log of what each work session accomplished.

---

## 2026-11-11 — Security review and fixes

- Reviewed what leaves the Mac, the clipboard handling, the API key, prompt injection, the two permissions, Sparkle updates, the release pipeline and the repository's history, then fixed what the review found. The choices made are in DECISIONS.md
- Panel and API: prompt tags that selected or pasted text can't forge, cut-off responses no longer accepted as finished, hidden context no longer sent unseen, an uncropped screenshot preview, requests that wait for the screen capture, results cleaned of hidden characters, the clipboard read only on request, and smaller fixes
- Clipboard and paste: `ClipboardRoute` gives the clipboard back when the app has read the paste and undoes a copy that arrives late. No synthetic ⌘C for terminals, remote desktops and virtual machines. Insert checks where the cursor is, and terminals need a second press
- Releases: the workflow is split into check, build and publish, with secrets in an approved `release` environment. Sparkle now requires a signed feed and checks an update before unpacking it. GRDB, Sparkle and XcodeGen are pinned. docs/RELEASING.md describes the new setup
- Verified: 266 tests pass, and passed 20 runs in a row, half of them with every CPU core busy. The app builds. A throwaway Release build and a throwaway key showed that the feed tool signs the feed once the app asks for it, and both signatures checked out independently. Lazy pasteboard delivery was checked between two processes on a private pasteboard
- Not verified: capture and paste in real apps with the new clipboard code, which needs an on-screen test. The new prompt format against the live API, which needs a few real rewrites. The workflows and `setup-release-secrets.sh`, which have not run since they changed. A real update from 0.2.0
- A second review of the merged changes found ten more points. Fixed: overlapping clipboard operations, a black flag emoji that could hide text, a saved key that macOS won't hand over being reported as missing, a fragile check in the setup script, and two duplicated helpers. `Package.resolved` turned out to be rewritten by Xcode as well as by `swift test`, so it is no longer committed. 271 tests pass
- Next for the maintainer: merge, run `mac/scripts/setup-release-secrets.sh`, add the two rulesets from docs/RELEASING.md, then try a few rewrites and pastes in Slack and Mail before tagging a release

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
- Verified: 200 tests pass, an ad hoc build works with no Apple account, a Release archive builds with hardened runtime, and the update feed is generated and signed correctly with a throwaway key. Not verified, because they need the maintainer's certificate and keys: the workflows have not run on GitHub, nothing has been signed through the new Developer ID path, and no installed app has updated itself yet
- Next: finish the setup in docs/RELEASING.md and publish the first release with automatic updates, then the bug pass and the landing page

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
