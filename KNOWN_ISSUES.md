# Known Issues

Active bugs, gotchas, and workarounds. Append entries with date.

---

## 2026-11-11 — The backdrop depends on a private window-server call

The slight blur behind the panel comes from `CGSSetWindowBackgroundBlurRadius`, which Apple doesn't document. If a future macOS removes it, `PanelBackdrop.isAvailable` turns false and the panel shows frosted glass with no backdrop, as 0.3.2 did. If it stays but behaves differently, the backdrop could look wrong: measure it again with the checkerboard method under Tooling gotchas. Its numbers were found on macOS 27.

---

## 2026-11-11 — Back sometimes did nothing, and the panel can feel slow

Up to 0.3.0, Apple's Writing Tools ran inside OmanAI's panel. After text in the panel was clicked or selected, macOS set up its floating Writing Tools button and a host window over the panel, which could sit on Back and take the click. The system log shows this as `CampoLightweightUI` events in OmanAI's process. Writing Tools is now off for OmanAI's own text, but Back has not been re-checked on screen. If it misses again, `/usr/bin/log show --last 1h --predicate 'subsystem == "com.romanbitca.oman"'` shows whether the press arrived.

The lag is not explained yet. macOS recorded no hang and never marked OmanAI unresponsive. Each time the panel opens with a focused text field, the system's text cursor indicator is moved about 60 times while the panel animates, and its service sometimes fails to connect (ViewBridge error 18).

---

## 2026-11-11 — Spending is an estimate

The Spending page prices the token counts Anthropic reports with list prices built into the app, so it can drift from the real bill. A request stopped before it finished counts only the output reported so far, which is usually just the first token. When Sonnet or Opus declines and a fallback model answers, only the answer is counted. Requests made with the same key outside OmanAI, or from another Mac, are not included. Requests from before this version were never recorded. The Anthropic Console has the actual bill.

---

## 2026-11-11 — A release needs no approval until the setup script has run

The release workflow and docs/RELEASING.md expect the six release secrets in a `release` environment that asks the maintainer for approval. On this repository the environment has no rules and the secrets are still stored on the repository itself, because `mac/scripts/setup-release-secrets.sh` has not run since it changed. GitHub created the environment empty when 0.2.1 was released, which is what it does with a missing one. Until the script runs, the build and publish jobs start without approval, and a workflow on any branch can read the secrets. Only someone who can push to the repository can add such a workflow, and only admins can push a `v*` tag. Fix: run the script once, as step 5 of docs/RELEASING.md describes.

---

## 2026-11-11 — A copy made within a second of a failed capture can be undone

When ⌘C brings nothing back in time, OmanAI watches the clipboard for one more second and undoes a text copy that arrives, because it is almost always the app's late answer. A copy you make yourself in that second, for example with ⌘C inside the panel, is undone too. The panel's Copy button is not affected.

---

## 2026-11-11 — Editors that copy a whole line when nothing is selected

VS Code and some other editors copy the current line when ⌘C is pressed with no selection. In an Electron editor, OmanAI reads the selection with ⌘C, so that line shows up as the selected text, and Replace would paste at the cursor instead of over the line. Select the text first. Detecting this copy needs the editor's own clipboard format and is not done yet.

---

## 2026-11-11 — No selection in terminals, remote desktops and virtual machines

OmanAI doesn't send its synthetic ⌘C to these apps, because there it can do more than copy: in a remote desktop or virtual machine it can arrive as Ctrl+C. A selection is still read where the app exposes it through Accessibility, as Terminal does. Otherwise the panel opens in Compose. The list of apps is in `SensitiveApps.swift`.

---

## 2026-11-11 — Insert can ask for a second press

Insert compares the focused element with the one from when the panel opened, and asks again if it differs. An app that hands out a new Accessibility element for the same field would cause one extra press. Pasting into a terminal always asks twice, because pasted text can run as a command.

---

## 2026-11-11 — The screenshot can still be a large popup

Invisible windows and windows smaller than 50 points are skipped, but a large popup in front of the document window, such as an emoji picker, is still what gets captured. The preview shows the whole picture, so check it before sending.

---

## 2026-11-10 — Freeze in AppKit's Password AutoFill check

The main thread spun at 100% in `NSAutoFillHeuristicController`, walking SwiftUI's key views (`FocusNavigationSequence.next`). It showed up after focus changes such as taking a screenshot, and buttons then looked broken. Worked around in `OmanMain.swift` with the `NSAutoFillHeuristicsEnabled` default. It could not be reproduced on demand, so if the app freezes again, run `sample $(pgrep -x OmanAI) 2` to see where it is stuck.

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

Accessibility is tied to the code signature. Going between an Apple Development build and a Developer ID build can leave OmanAI switched on in System Settings but not trusted, and pressing Allow then does nothing. The `tccd` log shows `Failed to match existing code requirement`. Remove it from the list with the minus button and allow it again, and do the same for Screen Recording. The saved API key may also ask for Keychain access once. Only install builds from `mac/scripts/release.sh`, which all share one signature requirement.

---

## 2026-11-10 — Xcode can refuse to create a Developer ID certificate

On an Individual team, Xcode's Manage Certificates failed with "This operation can only be performed by the Account Holder", even for the account holder. Creating the same certificate on developer.apple.com from a certificate request worked. Importing a certificate while iCloud is selected in Keychain Access fails with error -25294, so import into the login keychain.

---

## 2026-11-10 — Tooling gotchas for this repo

- Subagents launched with `isolation: "worktree"` start from `origin/main`, not the current branch. Have them run `git switch -c <branch> <commit>` first.
- `swift test` builds every test target, so concurrent module work needs separate worktrees or one module's half-written code breaks the others.
- A SwiftUI shape drawn above a `WindowDragArea` takes the click and does nothing with it, so mark it `.allowsHitTesting(false)`.
- Fully clear pixels in the panel pass clicks to the app behind. Liquid Glass in a custom `Shape` counts as clear, unlike glass in a capsule or rounded rectangle, and so did a dark bar drawn on it. A 2% white fill in the same shape, behind the drag area, makes it clickable. Unit tests can't see this: check with real mouse events.
- `log` is a zsh builtin, so reading the system log needs `/usr/bin/log`.
- Glass can be checked on screen, with the maintainer's OK: host the panel in a borderless panel under the menu bar, make it the key window, let it draw for about a second, and capture that area with `screencapture -R`. Glass in a window that isn't key is drawn flat and gray, which made several captures misleading. Control Center opens through Accessibility by pressing the "Control Center" item that `MenuBarAgent` owns in the menu bar (System Events can't see it); wait about three seconds before capturing it.
- To compare with Control Center by numbers, put a window with a black and white checkerboard of 32-point squares behind both, at level `.floating`. Per square, read the white level, the black level, and the width of the edge to the next square: the 10% to 90% width divided by 2.563 is the blur's sigma. The backdrop's numbers were found this way.
- The window server's blur (`CGSSetWindowBackgroundBlurRadius`) only shows where the window's own pixels have an alpha of at least 2/255. It is all or nothing there, and three units of radius blur by about one point. Blurs in stacked windows add as the root of the sum of their squares.
- `NSVisualEffectView.maskImage` ignores an image with only an alpha channel. Give it black pixels with the fade in their alpha.
- `gh` on this Mac has more than one account, and the active one may be a work account that can only read this repository. Then pushes and `gh variable get` fail with 403. Run them with the maintainer's account for that command only, `GH_TOKEN="$(gh auth token --user romanbitca)"`, rather than switching the active account.
- Don't check permissions by reading the panel's text through System Events: most of it isn't exposed. Read the `AUTHREQ_RESULT` lines in the `tccd` log instead.
- Liquid Glass can't be checked offscreen: `cacheDisplay` draws no glass, and any tinted glass blanks the whole bitmap. Real rendering needs a person looking at it, or Screen Recording permission.
- A backdrop made from `NSVisualEffectView` or from glass always shows a tint: a gray veil or card over a white app, a light one over a dark app. The maintainer rejected three such versions. Only the window server's blur is free of tint.
- The computer-use tools can't see OmanAI because it is menu-bar-only. Drive it with System Events (`click menu bar item 1 of menu bar 1` of process "OmanAI"), and allow for scripted clicks lagging under heavy CPU load.

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

