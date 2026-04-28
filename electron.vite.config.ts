import { resolve } from 'node:path'
import { defineConfig, externalizeDepsPlugin } from 'electron-vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
    build: {
      rollupOptions: {
        input: { index: resolve('electron/main.ts') },
      },
    },
    resolve: {
      alias: {
        '@shared': resolve('shared'),
        '@electron': resolve('electron'),
      },
    },
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
    build: {
      rollupOptions: {
        input: { index: resolve('electron/preload.ts') },
      },
    },
    resolve: {
      alias: {
        '@shared': resolve('shared'),
      },
    },
  },
  renderer: {
    root: '.',
    plugins: [react()],
    build: {
      rollupOptions: {
        input: { index: resolve('index.html') },
      },
    },
    resolve: {
      alias: {
        '@': resolve('src'),
        '@shared': resolve('shared'),
      },
    },
  },
})
