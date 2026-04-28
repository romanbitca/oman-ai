import { useEffect, useRef, useState } from 'react'
import { useWorkspaceStore } from '@/store/workspace-store'

export function WorkspaceSwitcher(): JSX.Element {
  const { current, workspaces, ready, load, switchTo, create } = useWorkspaceStore()
  const [open, setOpen] = useState(false)
  const [creating, setCreating] = useState(false)
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    void load()
  }, [load])

  useEffect(() => {
    if (!open) return
    function onClick(e: MouseEvent): void {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        closeMenu()
      }
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [open])

  function closeMenu(): void {
    setOpen(false)
    setCreating(false)
    setName('')
    setError(null)
  }

  async function handleCreate(): Promise<void> {
    setError(null)
    try {
      await create(name)
      closeMenu()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  async function handleSwitch(slug: string): Promise<void> {
    if (slug !== current?.slug) await switchTo(slug)
    closeMenu()
  }

  return (
    <div ref={ref} className="relative inline-block text-sm">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-2 rounded-md border border-border bg-secondary px-3 py-1.5 text-secondary-foreground hover:bg-accent"
      >
        <span className="font-medium">{ready ? (current?.slug ?? '—') : '…'}</span>
        <span className="text-muted-foreground">▾</span>
      </button>
      {open && (
        <div className="absolute left-0 top-full z-10 mt-1 w-56 rounded-md border border-border bg-popover p-1 text-popover-foreground shadow-md">
          {workspaces.map((ws) => (
            <button
              key={ws.slug}
              type="button"
              onClick={() => void handleSwitch(ws.slug)}
              className={`block w-full rounded-sm px-2 py-1.5 text-left hover:bg-accent ${
                ws.slug === current?.slug ? 'bg-accent' : ''
              }`}
            >
              {ws.slug}
            </button>
          ))}
          <div className="my-1 border-t border-border" />
          {!creating ? (
            <button
              type="button"
              onClick={() => setCreating(true)}
              className="block w-full rounded-sm px-2 py-1.5 text-left text-muted-foreground hover:bg-accent"
            >
              + New workspace
            </button>
          ) : (
            <div className="space-y-1 p-1">
              <input
                autoFocus
                value={name}
                onChange={(e) => setName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') void handleCreate()
                  if (e.key === 'Escape') closeMenu()
                }}
                placeholder="workspace name"
                className="w-full rounded-sm border border-border bg-background px-2 py-1 text-foreground outline-none focus:ring-1 focus:ring-ring"
              />
              {error && <p className="px-1 text-xs text-destructive">{error}</p>}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
