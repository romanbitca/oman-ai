# Security

OmanAI reads selected text, can see the window you are writing in, stores an API key and updates itself, so security reports matter a lot.

## Reporting a problem

Please don't open a public issue. Use GitHub's [private report form](https://github.com/romanbitca/oman-ai/security/advisories/new), and include the steps to reproduce the problem and the version you tested.

## What is supported

Only the latest release gets security fixes. OmanAI updates itself, so most people will get a fix within a day of its release.

## Things worth knowing

- The Anthropic API key is stored in the macOS Keychain, not in the database.
- Reading a selection in some apps uses a brief synthetic copy. The clipboard is put back as soon as the copy arrives, and a copy that arrives late is undone as well. Terminals, remote desktops and virtual machines are never sent that copy.
- The text you select, the context you paste and the screenshot reach the model as material, inside tags that carry a code the text can't know, so text that looks like an instruction stays text. The result is shown before anything is pasted, and nothing is pasted without your click.
- Updates are downloaded over HTTPS from this repository's releases. The update feed, its release notes and each update must carry an EdDSA signature that matches the public key built into the app, and an update is checked before it is unpacked. Releases are also signed with Developer ID and notarized by Apple. Version 0.2.0 was built before the feed and unpacking checks were turned on.
