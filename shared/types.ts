// Shared types between Electron main and renderer.

export type WorkspaceMeta = {
  slug: string
  path: string
  createdAt: number
}

export type OmanApi = {
  workspaces: {
    list: () => Promise<WorkspaceMeta[]>
    current: () => Promise<WorkspaceMeta | null>
    create: (name: string) => Promise<WorkspaceMeta>
    switch: (slug: string) => Promise<WorkspaceMeta>
  }
}

declare global {
  interface Window {
    omanApi: OmanApi
  }
}
