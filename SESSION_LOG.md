# Session Log

Date-stamped log of what each work session accomplished.

---

## 2026-04-28 — Project bootstrap

- Repo created at github.com/romanbitca/oman-ai
- Created README.md, CLAUDE.md, PLAN.md, DECISIONS.md, KNOWN_ISSUES.md, SESSION_LOG.md
- Stack and v1 scope locked
- Next: run Phase 1 (Skeleton) with Claude Code

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
