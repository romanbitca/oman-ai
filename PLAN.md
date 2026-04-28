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

## P2: SQLite and workspaces [DONE 2026-04-28]

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

## P3a: Mac audio binary (standalone) [IN PROGRESS]

Native Swift binary that captures system audio + microphone to chunked Opus files. Runs and verifies independently of Electron.

Requirements:
- Swift Package at `native/mac/AudioCapture/` builds CLI binary `oman-audio-mac`
- Output binary path: `native/mac/AudioCapture/.build/release/oman-audio-mac`
- Captures system audio via ScreenCaptureKit (SCStream + SCContentFilter for "all audio, no video")
- Captures microphone via AVAudioEngine
- Mixes system + mic into a single stereo Opus file (or two separate channels — Claude decides, log to DECISIONS.md)
- Encodes to .opus using libopus (install via `brew install opus opusfile`)
- If libopus integration is too painful, fallback to .wav and log in KNOWN_ISSUES.md as P3b-blocker
- Output: 30-second chunks named `{unix_timestamp}_{chunk_index}.opus` in `--output-dir`
- Reads JSON commands from stdin, one per line:
  - `{"cmd":"start","output_dir":"/abs/path"}` — begin recording
  - `{"cmd":"stop"}` — flush current chunk, write manifest, exit
- Writes `manifest.json` on stop with `{ chunks: [{filename, start_ms, end_ms, duration_ms}], started_at, stopped_at }`
- Handles SIGTERM by flushing current chunk and writing manifest before exit
- Logs to stderr; stdout reserved for status JSON: `{"status":"recording"}`, `{"status":"chunk_written","file":"..."}`, `{"status":"stopped"}`

Required Info.plist / entitlements (research and document):
- `NSMicrophoneUsageDescription` — "oman records meeting audio for transcription"
- ScreenCaptureKit needs Screen Recording permission granted via System Settings on first run
- TCC will prompt on first launch; binary must handle "denied" gracefully and exit with status code 2

Acceptance:
- Build: `cd native/mac/AudioCapture && swift build -c release` succeeds
- Run from terminal:
```
  mkdir -p /tmp/oman-test
  echo '{"cmd":"start","output_dir":"/tmp/oman-test"}' | ./.build/release/oman-audio-mac
  # talk for 60 seconds while playing music in another app
  # in another terminal: echo '{"cmd":"stop"}' > the binary's stdin (use a fifo or run interactively)
```
- Result: 2 chunks (`*.opus` files) + `manifest.json` in `/tmp/oman-test`
- Each chunk plays in QuickTime or `ffplay` and contains BOTH the user's voice AND the system audio (music)
- Total duration ≈ 60 seconds across all chunks
- Killing binary mid-recording with SIGTERM: chunk + manifest still present, last chunk shorter than 30s

Out of scope for P3a: Electron integration, IPC, UI, DB writes, ffmpeg merging.

---

## P3b: Electron integration of audio binary [TODO]

Wire the P3a binary into Electron with manual record button.

Requirements:
- `electron/services/audio-recorder.ts` spawns `oman-audio-mac` as child_process
- Detects binary path: `path.join(app.isPackaged ? process.resourcesPath : __dirname, '../../native/mac/AudioCapture/.build/release/oman-audio-mac')` — adjust for actual layout
- IPC channels: `recording:start` (creates meeting row, returns meeting_id), `recording:stop` (returns audio dir path), `recording:status`
- Audio output dir: `~/Library/Application Support/oman/audio/{workspace_slug}/{meeting_id}/`
- On `recording:start`: insert meetings row with `started_at = now`, generate UUID for `id`, source = "manual"
- Add `getDb()` export to workspace-manager.ts (handoff note from P2)
- Renderer:
  - Big record button on main view (red when recording, grey when idle)
  - Shows elapsed time during recording
  - Disables workspace switcher while recording (greyed out + tooltip)
- Zustand: `recording-store.ts` with `{ isRecording, meetingId, startedAt }`

Acceptance:
- Click Record. Talk + play music for 30s. Click Stop.
- Audio dir contains 1+ chunks + manifest.json
- DB row exists in current workspace's `meetings` table with started_at, ended_at, audio_path = chunk dir
- Workspace switcher visibly disabled during recording
- typecheck + lint pass
- No console errors

Out of scope: chunk merging, transcription, screen capture.

---

## P3c: Chunk merge + audio_path finalization [TODO]

Merge chunks into single file post-recording.

Requirements:
- After `recording:stop`, run `ffmpeg` to concatenate chunks in manifest order into `recording.opus` in the same dir
- Bundle ffmpeg binary in `resources/ffmpeg/mac/ffmpeg` (download arm64 static build from evermeet.cx, document source in DECISIONS.md)
- Update meetings row: `audio_path` = full path to `recording.opus`, `ended_at` = manifest.stopped_at
- Optional: delete chunks after successful merge (keep manifest.json for forensics)
- If merge fails: log error, keep chunks, set audio_path to chunk dir, log to KNOWN_ISSUES.md

Acceptance:
- After stopping a 60s recording, `recording.opus` exists, plays cleanly, duration ≈ 60s
- DB row's audio_path points at `recording.opus`
- Workspace dir contains: `recording.opus`, `manifest.json`, (optionally chunks deleted)

Out of scope: transcription (P5).

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
