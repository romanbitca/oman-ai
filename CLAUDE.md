# Claude Code Instructions

## Project context

oman is an Electron meeting recorder for macOS and Windows. Local-first SQLite. Multi-workspace.

Always read PLAN.md, DECISIONS.md, KNOWN_ISSUES.md, and SESSION_LOG.md at the start of every session before writing code.

## Working agreement

- Implement only what the current task asks. No extra features.
- If a decision needs to be made that is not in DECISIONS.md, stop and ask the user.
- Update KNOWN_ISSUES.md when you discover bugs or workarounds.
- Update SESSION_LOG.md at the end of every session with what was done, dated.
- Never rewrite working code unless explicitly asked.
- Run `npm run typecheck` and `npm run lint` after changes. Fix errors before declaring done.
- Commit at logical milestones with clear messages. Do not commit broken code.

## Style

- TypeScript strict mode
- No `any` unless commented why
- Prefer explicit imports
- Comments only for non-obvious logic
- File names: kebab-case
- React components: PascalCase
- Functions and variables: camelCase

## Stack constraints

- Electron + electron-vite + electron-builder
- React 18 + TypeScript
- Tailwind CSS + shadcn/ui (neutral theme, dark mode default)
- Zustand for renderer state
- better-sqlite3 for storage
- Path aliases: @/ for src/, @shared/ for shared/, @electron/ for electron/

## Current phase

See PLAN.md - phase marked [IN PROGRESS]
