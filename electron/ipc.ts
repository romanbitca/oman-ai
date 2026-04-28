import { ipcMain } from 'electron'
import {
  createWorkspace,
  getCurrentWorkspace,
  listWorkspaces,
  switchWorkspace,
} from './services/workspace-manager'

export function registerIpc(): void {
  ipcMain.handle('workspace:list', () => listWorkspaces())
  ipcMain.handle('workspace:current', () => getCurrentWorkspace())
  ipcMain.handle('workspace:create', (_event, name: string) => {
    const ws = createWorkspace(name)
    return switchWorkspace(ws.slug)
  })
  ipcMain.handle('workspace:switch', (_event, slug: string) => switchWorkspace(slug))
}
