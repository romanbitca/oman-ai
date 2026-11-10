# Known Issues

Active bugs, gotchas, and workarounds. Append entries with date.

---

## 2026-11-10 — Freeze in AppKit's Password AutoFill check

The main thread spun at 100% in `NSAutoFillHeuristicController`, walking SwiftUI's key views (`FocusNavigationSequence.next`). It showed up after focus changes such as taking a screenshot, and buttons then looked broken. Worked around in `OmanMain.swift` with the `NSAutoFillHeuristicsEnabled` default. It could not be reproduced on demand, so if the app freezes again, run `sample $(pgrep -x oman) 2` to see where it is stuck.

---

## 2026-11-10 — Apple's on-device model has hard limits

Its context is 4,096 tokens, so only about 4,000 characters of style samples are used, and it is much weaker at matching a voice than Claude. It ignores screenshots and quality settings.

---

## 2026-11-10 — Compose: Insert where text can't go loses the draft

Insert sends Cmd+V and closes the panel. If nothing editable has focus, the paste does nothing, and macOS gives no way to detect that, so the draft is gone and has to be regenerated.

---

## 2026-11-10 — Cmd+C and Cmd+V use the physical C and V keys

`KeyEvents` posts key codes 8 and 9. QWERTY-based layouts and Cyrillic work. Dvorak-style layouts would send the wrong shortcut. Fix with a layout lookup if it ever matters.

---

## 2026-11-10 — Electron apps use the clipboard route

Slack and other Electron apps don't expose selected text through Accessibility unless accessibility mode is forced on, which we avoid. The selection is read with a synthetic Cmd+C and the clipboard is restored straight after, but a clipboard history app can still record that brief copy. The paste itself is marked transient, so those apps skip it.

---

## 2026-11-10 — A build in a temporary folder never appears in privacy settings

macOS records the permission request, but the lookup by bundle ID fails (`kLSApplicationNotFoundErr` in the `tccd` log), so System Settings has nothing to list. Test permissions from a copy in `/Applications`.

---

## 2026-11-10 — Changing the signature breaks privacy grants

Accessibility is tied to the code signature. Going between an Apple Development build and a Developer ID build can leave oman switched on in System Settings but not trusted. Remove it from the list and allow it again. The saved API key may also ask for Keychain access once. `mac/scripts/release.sh` and the Install command in CLAUDE.md produce different signatures, so keep to one of them for the copy in `/Applications`.

---

## 2026-11-10 — Tooling gotchas for this repo

- Subagents launched with `isolation: "worktree"` start from `origin/main`, not the current branch. Have them run `git switch -c <branch> <commit>` first.
- `swift test` builds every test target, so concurrent module work needs separate worktrees or one module's half-written code breaks the others.
- Liquid Glass can't be checked offscreen: `cacheDisplay` draws no glass, and any tinted glass blanks the whole bitmap. Real rendering needs a person looking at it, or Screen Recording permission.
- The computer-use tools can't see oman because it is menu-bar-only. Drive it with System Events (`click menu bar item 1 of menu bar 1` of process "oman"), and allow for scripted clicks lagging under heavy CPU load.

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

