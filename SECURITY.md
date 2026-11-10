# Security

OmanAI reads selected text, can see the window you are writing in, stores an API key and updates itself, so security reports matter a lot.

## Reporting a problem

Please don't open a public issue. Use GitHub's [private report form](https://github.com/romanbitca/oman-ai/security/advisories/new), and include the steps to reproduce the problem and the version you tested.

## What is supported

Only the latest release gets security fixes. OmanAI updates itself, so most people will get a fix within a day of its release.

## Things worth knowing

- The Anthropic API key is stored in the macOS Keychain, not in the database.
- Reading a selection in some apps uses a brief synthetic copy, and the clipboard is restored straight after.
- Updates are downloaded over HTTPS from this repository's releases. Each one must carry an EdDSA signature that matches the public key built into the app, and a valid Developer ID signature from the same team.
