import Database from 'better-sqlite3'
import { app } from 'electron'
import { existsSync, mkdirSync, readdirSync, statSync, unlinkSync } from 'node:fs'
import { join } from 'node:path'
import type { WorkspaceMeta } from '@shared/types'
import { applyMigrations, seedSettings } from './migrations'

let currentDb: Database.Database | null = null
let currentSlug: string | null = null

function workspacesDir(): string {
  return join(app.getPath('userData'), 'workspaces')
}

function workspacePath(slug: string): string {
  return join(workspacesDir(), `${slug}.db`)
}

function ensureDir(): void {
  const dir = workspacesDir()
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
}

// Slug = lowercase, alphanumeric, dash-separated.
function slugify(name: string): string {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}

function getMeta(slug: string): WorkspaceMeta {
  const path = workspacePath(slug)
  const stat = statSync(path)
  return { slug, path, createdAt: stat.birthtimeMs }
}

function openAndMigrate(slug: string): Database.Database {
  ensureDir()
  const path = workspacePath(slug)
  const isNew = !existsSync(path)
  const db = new Database(path)
  db.pragma('journal_mode = WAL')
  applyMigrations(db)
  if (isNew) seedSettings(db)
  return db
}

export function listWorkspaces(): WorkspaceMeta[] {
  const dir = workspacesDir()
  if (!existsSync(dir)) return []
  return readdirSync(dir)
    .filter((f) => f.endsWith('.db'))
    .map((f) => getMeta(f.replace(/\.db$/, '')))
    .sort((a, b) => a.createdAt - b.createdAt)
}

export function getCurrentWorkspace(): WorkspaceMeta | null {
  return currentSlug ? getMeta(currentSlug) : null
}

export function switchWorkspace(slug: string): WorkspaceMeta {
  if (!existsSync(workspacePath(slug))) {
    throw new Error(`Workspace "${slug}" does not exist.`)
  }
  if (currentSlug === slug && currentDb) return getMeta(slug)
  if (currentDb) currentDb.close()
  currentDb = openAndMigrate(slug)
  currentSlug = slug
  return getMeta(slug)
}

export function createWorkspace(name: string): WorkspaceMeta {
  const slug = slugify(name)
  if (!slug) throw new Error('Workspace name cannot be empty.')
  if (existsSync(workspacePath(slug))) {
    throw new Error(`Workspace "${slug}" already exists.`)
  }
  const db = openAndMigrate(slug)
  db.close()
  return getMeta(slug)
}

export function deleteWorkspace(slug: string): void {
  if (currentSlug === slug) {
    throw new Error('Cannot delete the active workspace.')
  }
  const path = workspacePath(slug)
  if (existsSync(path)) unlinkSync(path)
}

// Auto-creates `personal` if no workspaces exist, then switches to the
// oldest workspace (by creation time). Returns the active workspace.
export function initWorkspaces(): WorkspaceMeta {
  ensureDir()
  let list = listWorkspaces()
  if (list.length === 0) {
    createWorkspace('personal')
    list = listWorkspaces()
  }
  return switchWorkspace(list[0].slug)
}

export function closeCurrent(): void {
  if (currentDb) {
    currentDb.close()
    currentDb = null
    currentSlug = null
  }
}
