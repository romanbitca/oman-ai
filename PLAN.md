# Plan

Phased roadmap. Mark each phase with status: [TODO], [IN PROGRESS], [DONE date], [BLOCKED reason].

---

# Writing tool (current focus)

Native Swift menu bar app in `mac/`. See DECISIONS.md, 2026-11-10.

## W1: Capture and replace [IN PROGRESS]

Clicking the menu bar icon reads the selected text from the frontmost app without taking focus. Replace pastes over it and restores the clipboard.

Acceptance:
- Works in Slack, Telegram, Mail and Gmail in Chrome
- The selection survives opening the panel and typing in it
- The clipboard holds its previous contents afterwards
- If the selection changed, nothing is pasted and the panel says so

## W2: Panel, Claude and Compose [IN PROGRESS]

Panel laid out like Apple's Writing Tools: Proofread, Rewrite, free-text instruction, Compose. Streaming result with Replace or Insert, Copy, Try again and a typed adjustment. API key and model picker in Settings, with Haiku 5.5 as the default model.

Acceptance:
- A rewrite streams into the panel and Replace puts it in the source app
- With nothing selected the panel opens in Compose, and Insert pastes at the cursor
- API errors appear in the panel and the original text is untouched

## W3: Styles [IN PROGRESS]

Settings editor to create styles from pasted messages, with an optional note and a test sentence. Style buttons in the panel. The last style used in each app is preselected.

Acceptance:
- Styles persist across launches
- A second request with the same style shows `cache_read_input_tokens > 0`
- A rewrite sounds like the person who wrote the samples

## W4: Context [IN PROGRESS]

Paste box, Use clipboard, Pin, and a screenshot of the window being written in with a thumbnail preview.

Acceptance:
- Context changes the result, and nothing is sent that the panel did not show
- Only the source window is captured
- Screen Recording permission is requested only on first use

## W5: Finish [IN PROGRESS]

First-run setup in the panel, launch at login, signed build.

Acceptance:
- A fresh install reaches a working rewrite by following the panel alone
- Accessibility permission survives a rebuild

## W6: Shortcuts, floating panel, on-device model [IN PROGRESS]

Assignable global and result shortcuts, a redesigned Settings with more options, a pinned panel that works as a floating window, and Apple's on-device model as an alternative to Claude.

Acceptance:
- A global shortcut runs its action on the selection from any app
- A pinned panel can be dragged, stays on top, and keeps its position
- Rewrite and Compose work on the on-device model with no API key
- The panel does not freeze after focus changes, such as taking a screenshot

## W7: Releases and open source [DONE 2026-11-11]

Signed and notarized builds published from a Git tag by GitHub Actions, automatic updates through Sparkle and GitHub Releases, and the files an open-source project needs.

Acceptance:
- Pushing a tag such as `v0.2.0` publishes a notarized zip and `appcast.xml` on GitHub Releases
- An older installed version finds the new one and installs it, and Accessibility keeps working afterwards
- Someone without an Apple Developer account can clone the repo, build it and run the tests

## W8: Explain and spending [IN PROGRESS]

An Explain action that tells the person how a reader will understand their text, smaller action buttons, and a Spending page in Settings with charts per day and per week.

Acceptance:
- Explain on a selection says what a reader will take from it and names anything unclear, in the language of the text
- An explanation can't be pasted, and Try again gives a new reading
- Proofread, Rewrite and Explain fit on one row
- Spending shows today, this week, the last 14 days and the last 8 weeks, and a Claude request appears there straight after it finishes

## W9: Choices in the panel, Settings and the icon [IN PROGRESS]

The panel hangs where Control Center does. Templates and context are plain choices that start nothing. Settings and the menu bar icon are redesigned from proposals the maintainer picks.

Acceptance:
- The first tile starts 12 points below the menu bar, as Control Center's first module does
- A template chip only chooses. As written is first and means no template. Proofread, Rewrite and Compose use the chosen one
- The templates stay on one line behind a thin divider and scroll sideways when there are many
- Screen, Messages and Clipboard each turn on and off, in any combination, and only what is on is sent
- Settings is a window with a tab for each page in its toolbar, built from macOS's own controls, and as tall as the page it shows
- A style is edited in a sheet, and deleting it asks first
- Spending can be read for today, this week, this month, last month and all time, with the requests, the tokens and a list by model
- The menu bar icon is the single wave the maintainer chose

---

# Meeting recorder (parked 2026-11-10)

Everything below is parked until the writing tool ships. P1 and P2 produced an Electron skeleton, which is kept on the `archive/meeting-recorder` branch.

---

## W10: Answers that hold up [IN PROGRESS]

The prompts are judged by what the real models answer, many times over, and not by one reply. On 12 November 2026 the maintainer said yes to the two changes a person can see, Proofread about a second slower on Haiku and As written keeping lower case, and they ship in 0.3.5.

Acceptance:
- Proofread corrects spelling, grammar and apostrophes and keeps the person's wording and shorthand, on each Claude model at each quality
- With As written, a message typed in lower case stays in lower case, and a missed capital in text that mostly has them is put right
- With a template, capital letters, apostrophes and the final full stop follow the template's messages, in both directions, and nothing is added
- Explain gives only the reading, in the language of the text, and says so when a text reads clearly
- `LiveWritingTests`, run with a key, has no more than 1 answer in 20 failing a check
- Each date under the Spending chart sits under its own bar, and none is cut off
- The website runs on an nginx image that still gets updates

---

## W11: What Proofread changed [IN PROGRESS]

After a proofread the panel shows what changed, in one of two ways chosen in Settings.

Acceptance:
- With At once, each changed word is tinted as soon as the result appears, and the count in the header shows the words they replaced, struck through
- With When I ask, the result stays plain until Show changes is clicked
- "No changes" when nothing was corrected, and Show original when most of the words changed
- Replace and Copy deliver the corrected text, whatever is on show
- ⌘O does what the header button does

---

## W12: Dictation [IN PROGRESS]

Speak instead of typing, in any app or in the panel, with the words shown live and turned into text on the Mac.

Acceptance:
- Holding Hold to dictate shows the glass pill with the words as they are said, and letting go pastes them at the cursor
- Start or stop a long dictation starts listening on one press and pastes on the next; the pill's check button and the menu bar icon finish it too
- Escape cancels and pastes nothing
- The pill hangs under the menu bar icon, or sits at the bottom of the screen when Settings says so, and never takes the keyboard
- Settings chooses its look: Card, with the seconds and Done above the words in a glass card, or Floating, with the words on a soft blur above them
- In the panel, the microphone buttons and the shortcuts put the words into the field being typed in, live
- Apple's model works on macOS 26 and later with no download from OmanAI; Parakeet and Whisper download from Settings with progress, and can be removed
- The language list follows the model, with Automatic first where the model can work the language out
- With a live model, the first words show within about a second of being said
- Settings lists the models with their languages, speed and size, and downloads, chooses and deletes them
- The person's own words are written their way, filler words go if Settings says so, and a downloaded model is unloaded after the time Settings gives
- Cancel and Done sit beside the words for a long dictation
- With Keep transcripts on, each dictation's text is listed in Settings with Copy and Delete; the sound is never kept
- Without the microphone permission, or with a model still to download, the pill says what to do

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

## P3a: Mac audio binary (standalone) [BLOCKED parked 2026-11-10, writing tool comes first]

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
