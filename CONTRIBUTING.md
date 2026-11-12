# Contributing to OmanAI

Thanks for helping. Bug reports, fixes and small improvements are all welcome. For anything larger, please open an issue first so we can agree on the approach before you spend time on it.

## Getting set up

Follow "Build from source" in the [README](README.md). You don't need an Apple Developer account.

To test reading and pasting text, copy your build to `/Applications` and allow Accessibility for that copy. macOS won't list a build that runs from a temporary folder, and it treats each rebuild as a new app. [KNOWN_ISSUES.md](KNOWN_ISSUES.md) has more on this.

## Before you open a pull request

- Run `swift test` in `mac/OmanKit`, and build the app.
- Add or update tests when behaviour changes.
- Keep each pull request to one change, and say why it is needed.
- Include a screenshot for visible changes.

## Code style

- Swift 6 language mode with strict concurrency.
- No force unwraps or `fatalError` outside tests, unless a comment says why.
- Comments only where the logic isn't obvious.
- Logic goes in the `mac/OmanKit` package. The app target stays a thin shell.

## Design rules

- Everything opens from the menu bar icon. Nothing may appear in or near the text field being edited. The one exception is the dictation pill, which the person can move to the bottom of the screen in Settings.
- No bouncing or springy motion anywhere, and no animation at all in Settings.
- Writing goes through the Anthropic API or Apple's on-device model. Please open an issue before proposing another provider.
- Dictation runs on the Mac only, through Apple's speech model, NVIDIA's Parakeet and Nemotron models with FluidAudio, or Whisper with WhisperKit. The sound is never sent anywhere or kept.

The reasoning behind these and other choices is in [DECISIONS.md](DECISIONS.md).

## Licensing

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
