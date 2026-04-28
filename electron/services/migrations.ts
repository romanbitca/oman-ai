import type Database from 'better-sqlite3'

const SCHEMA_V1 = `
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
`

// Each entry is a migration from version i -> i+1, applied in order.
// Bump SCHEMA_VERSION when adding a migration.
const migrations: Array<(db: Database.Database) => void> = [(db) => db.exec(SCHEMA_V1)]

export const SCHEMA_VERSION = migrations.length

export function applyMigrations(db: Database.Database): void {
  const current = db.pragma('user_version', { simple: true }) as number
  for (let i = current; i < migrations.length; i++) {
    const apply = db.transaction(() => {
      migrations[i](db)
      db.pragma(`user_version = ${i + 1}`)
    })
    apply()
  }
}

export function seedSettings(db: Database.Database): void {
  const stmt = db.prepare('INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)')
  stmt.run('transcription_mode', 'local')
  stmt.run('anthropic_api_key', null)
  stmt.run('drive_upload', 'false')
}
