# Plan

Phased roadmap. Mark each phase with status: [TODO], [IN PROGRESS], [DONE date], [BLOCKED reason].

---

## P1: Skeleton [DONE 2026-04-28]

Set up Electron app: electron-vite, TypeScript, React 18, Tailwind, shadcn/ui, Zustand, ESLint, Prettier.

Requirements:
- electron-vite for build, electron-builder for packaging
- React renderer in src/, Electron main in electron/, preload in electron/preload.ts
- Path aliases: @/ for src/, @shared/ for shared/, @electron/ for electron/
- Tailwind configured with dark mode default
- shadcn/ui initialized with neutral base color
- Scripts: dev, build, dist:mac, dist:win, typecheck, lint
- electron-builder.yml configured for mac (dmg) and win (nsis), GitHub publish target
- System tray icon (placeholder PNG) toggles main window visibility
- Main window: 1200x800, minWidth 900, minHeight 600
- Empty React app showing "oman" centered, dark theme

Acceptance:
- `npm run dev` opens the app on Mac
- Tray icon appears, click toggles main window
- `npm run typecheck` and `npm run lint` pass
- No errors in dev console

---

## P2: SQLite and workspaces [TODO]

Add better-sqlite3 with multi-workspace support.

Requirements:
- Workspaces stored at `~/Library/Application Support/oman/workspaces/{slug}.db` on Mac, `%APPDATA%/oman/workspaces/{slug}.db` on Windows
- Each workspace is its own SQLite file
- Schema (see below) with simple version-based migrations
- Service `electron/services/workspace-manager.ts`: list, create, switch, delete
- IPC handlers in `electron/ipc.ts`
- Top-left workspace switcher in UI: shows current workspace, click to switch or create new
- On first launch: auto-create workspace `personal`
- Settings table seeded: `transcription_mode=local`, `anthropic_api_key=null`, `drive_upload=false`
- Zustand store for current workspace; reload meetings on switch

Schema:
```sql
CREATE TABLE meetings (
  id TEXT PRIMARY KEY,
  title TEXT,
  started_at INTEGER,
  ended_at INTEGER,
  source TEXT,
  calendar_event_id TEXT,
  audio_path TEXT,
  transcript TEXT,
  speaker_timeline TEXT,
  participants TEXT,
  folder_id TEXT,
  drive_file_id TEXT,
  drive_uploaded_at INTEGER
);

CREATE TABLE folders (
  id TEXT PRIMARY KEY,
  name TEXT,
  parent_id TEXT
);

CREATE TABLE tags (
  id TEXT PRIMARY KEY,
  name TEXT
);

CREATE TABLE meeting_tags (
  meeting_id TEXT,
  tag_id TEXT,
  PRIMARY KEY(meeting_id, tag_id)
);

CREATE TABLE screenshots (
  id TEXT PRIMARY KEY,
  meeting_id TEXT,
  taken_at INTEGER,
  file_path TEXT,
  ocr_text TEXT
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

CREATE VIRTUAL TABLE meetings_fts USING fts5(
  title, transcript, content=meetings, content_rowid=rowid
);
```

Acceptance:
- App launches and creates `personal.db` automatically
- Workspace switcher works, switching loads different DB
- Creating a new workspace adds a new .db file
- All schema tables exist after first run

---

## P3: Audio recording on Mac [TODO]

Native Swift binary captures system audio + mic to chunked .opus files.

Requirements:
- `native/mac/AudioCapture/` Swift Package builds CLI binary `oman-audio-mac`
- Uses ScreenCaptureKit for system audio
- Uses AVAudioEngine for microphone
- Encodes to .opus (or .wav fallback)
- Writes 30-second chunks: `{timestamp}_{chunk_index}.opus`
- Reads JSON commands on stdin: `{"cmd":"start","output_dir":"..."}` and `{"cmd":"stop"}`
- On stop, writes `manifest.json` listing chunks
- Handles SIGTERM, flushes current chunk
- Crash leaves partial chunks recoverable

Electron side:
- `electron/services/audio-recorder.ts` spawns binary
- IPC: `startRecording(meetingId)`, `stopRecording()`
- Audio under `~/Library/Application Support/oman/audio/{workspace}/{meeting_id}/`
- Manual record button on UI, shows elapsed time
- On stop: merge chunks via ffmpeg, update meeting row

Required entitlements:
- NSMicrophoneUsageDescription
- ScreenCaptureKit permissions
- Code signing entitlement file

Acceptance:
- Click Record, talk for 1 min, click Stop
- File appears at expected path, plays back correctly with both mic and system audio
- DB row created with audio_path

---

## P4: Meeting detection [TODO]

(spec TBD before starting)

---

## P5: Local Whisper transcription [TODO]

(spec TBD before starting)

---

## P6: Speaker tracking via AX tree (Mac) [TODO]

(spec TBD before starting)

---

## P7: Screen capture every 5 seconds [TODO]

(spec TBD before starting)

---

## P8: UI build (Granola-style two-pane) [TODO]

(spec TBD before starting)

---

## P9: Google integrations (OAuth, Calendar, Drive) [TODO]

(spec TBD before starting)

---

## P10: Cloud transcription option (Deepgram) [TODO]

(spec TBD before starting)

---

## P11: Windows port [TODO]

(spec TBD before starting)

---

## P12: Distribution (GitHub releases, auto-update, signing) [TODO]

(spec TBD before starting)
