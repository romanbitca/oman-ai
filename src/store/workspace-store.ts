import { create } from 'zustand'
import type { WorkspaceMeta } from '@shared/types'

type WorkspaceStore = {
  current: WorkspaceMeta | null
  workspaces: WorkspaceMeta[]
  ready: boolean
  load: () => Promise<void>
  switchTo: (slug: string) => Promise<void>
  create: (name: string) => Promise<void>
}

export const useWorkspaceStore = create<WorkspaceStore>((set) => ({
  current: null,
  workspaces: [],
  ready: false,
  load: async () => {
    const [workspaces, current] = await Promise.all([
      window.omanApi.workspaces.list(),
      window.omanApi.workspaces.current(),
    ])
    set({ workspaces, current, ready: true })
  },
  switchTo: async (slug) => {
    const ws = await window.omanApi.workspaces.switch(slug)
    set({ current: ws })
  },
  create: async (name) => {
    const ws = await window.omanApi.workspaces.create(name)
    const workspaces = await window.omanApi.workspaces.list()
    set({ current: ws, workspaces })
  },
}))
