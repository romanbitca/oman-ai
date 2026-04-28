# Session Log

Date-stamped log of what each work session accomplished.

---

## 2026-04-28 — Project bootstrap

- Repo created at github.com/romanbitca/oman-ai
- Created README.md, CLAUDE.md, PLAN.md, DECISIONS.md, KNOWN_ISSUES.md, SESSION_LOG.md
- Stack and v1 scope locked
- Next: run Phase 1 (Skeleton) with Claude Code

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
- Next: P2 — SQLite + workspaces
