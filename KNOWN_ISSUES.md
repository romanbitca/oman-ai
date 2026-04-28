# Known Issues

Active bugs, gotchas, and workarounds. Append entries with date.

---

## 2026-04-28 — Renderer `sandbox: false` (ESM preload constraint)

The preload script is emitted as ESM (`out/preload/index.mjs`) because `package.json` has `"type": "module"`. Electron 33's renderer sandbox does not load ESM preload scripts — combining `sandbox: true` with an `.mjs` preload makes the renderer fail to start (Electron exits silently shortly after window creation).

Workaround: `sandbox: false` in `webPreferences`. `contextIsolation: true` and `nodeIntegration: false` are still on, so the renderer cannot directly touch Node APIs.

To re-enable `sandbox: true` later, either: (a) emit preload as CommonJS (`.cjs`) by overriding electron-vite's preload output, or (b) drop `"type": "module"` from `package.json` and let everything default to CJS in main/preload. Revisit during P12 (distribution) when hardening.

---

## 2026-04-28 — better-sqlite3 ABI rebuild required after every install

`better-sqlite3` ships prebuilt binaries for Node, not Electron. With Electron 33 (different `NODE_MODULE_VERSION`), a fresh `npm install` followed by `npm run dev` would otherwise fail with a native-binding mismatch the first time the main process imports the module.

Workaround: `"postinstall": "electron-builder install-app-deps"` in `package.json`. This invokes `@electron/rebuild` against the configured Electron version automatically after every `npm install`.

If a fresh clone ever errors with "was compiled against a different Node.js version" / `NODE_MODULE_VERSION`, the postinstall didn't run (e.g. `--ignore-scripts`); fix with `npx electron-builder install-app-deps`. Will need re-running whenever Electron's major version is bumped.

