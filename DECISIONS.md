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
