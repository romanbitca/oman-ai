import { contextBridge, ipcRenderer } from 'electron'
import type { OmanApi, WorkspaceMeta } from '@shared/types'

const omanApi: OmanApi = {
  workspaces: {
    list: (): Promise<WorkspaceMeta[]> => ipcRenderer.invoke('workspace:list'),
    current: (): Promise<WorkspaceMeta | null> => ipcRenderer.invoke('workspace:current'),
    create: (name: string): Promise<WorkspaceMeta> => ipcRenderer.invoke('workspace:create', name),
    switch: (slug: string): Promise<WorkspaceMeta> => ipcRenderer.invoke('workspace:switch', slug),
  },
}

contextBridge.exposeInMainWorld('omanApi', omanApi)
