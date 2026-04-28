import { Tray, Menu, app, nativeImage } from 'electron'
import { join } from 'node:path'

let tray: Tray | null = null

export function createTray(onToggle: () => void): void {
  const iconPath = app.isPackaged
    ? join(process.resourcesPath, 'tray-icon.png')
    : join(app.getAppPath(), 'resources/tray-icon.png')

  const image = nativeImage.createFromPath(iconPath)
  // Template image auto-inverts to match menu bar appearance on macOS.
  if (process.platform === 'darwin') image.setTemplateImage(true)

  tray = new Tray(image)
  tray.setToolTip('oman')
  tray.on('click', onToggle)

  const menu = Menu.buildFromTemplate([
    { label: 'Show / Hide', click: onToggle },
    { type: 'separator' },
    { label: 'Quit', role: 'quit' },
  ])
  tray.setContextMenu(menu)
}

export function destroyTray(): void {
  tray?.destroy()
  tray = null
}
