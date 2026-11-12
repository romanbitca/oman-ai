# Session Log

Date-stamped log of what each work session accomplished.

---

## 2026-11-12 — Dictation

- Asked for by the maintainer, after the dictation app Handy. The maintainer then asked the assistant to make the remaining choices itself; they are in DECISIONS.md, and the phase is W12 in PLAN.md
- Three models, all on the Mac: Apple's (SpeechAnalyzer, 68 languages on macOS 27), Parakeet Ultra through FluidAudio and Whisper large-v3 turbo through WhisperKit, both pinned to their release commits. Each was checked on a sentence spoken by `say`; all three wrote it word for word. Parakeet's download comes to 632 MB and Whisper's to 629 MB
- Global shortcuts can now be held: Carbon also reports when their keys are let go. Hold to dictate and Start or stop a long dictation are new, empty at first; Escape is taken only while a dictation runs
- A glass pill shows the live words while dictating into another app, under the menu bar icon or at the bottom of the screen; the menu bar icon's wave moves with the voice. In the panel, a microphone beside each field puts the words there as they are said
- Settings has a Dictation tab, and kept transcripts go in a new `dictations` table, text only
- The app asks for the microphone, and release builds carry the audio-input entitlement. The Debug build was checked for both, and Parakeet's unused parts, such as its 87 MB prebuilt text normaliser, are not in it
- 458 tests pass, the temporary harness's included. The app builds, and its build copy was unregistered and deleted
- Nine looks for the pill were drawn as moving mockups. The maintainer chose two, Card with the seconds and Done above the words and Floating with the words on a soft blur, and Settings chooses between them; Card is the default. Done now sits outside the words in both
- Not yet done: a real microphone, the pill on the screen, the documentation page and pictures

## 2026-11-12 — A sitemap for crawlers

- 9h Agent's crawler marked the site unreachable. Cloudflare's log shows it answered all three of the crawler's requests and blocked nothing: robots.txt and the home page with 200, and `/sitemap.xml` with 404 because there was none. Run locally, the crawler's own code allows every page and reads both pages, so its read failed on 9h's server after the download
- At the maintainer's request, added `site/sitemap.xml` with the home page and the docs, so a crawler finds both without following links. From the site's own container it comes as `text/xml`, a type the crawler accepts, and the crawler's sitemap reader takes both addresses from it

## 2026-11-12 — A chat assistant on the website

- At the maintainer's request, added 9h Digital's chat assistant to both pages, and allowed its address for scripts and connections in the site's response headers (see DECISIONS.md). Read the assistant's script first to see what it loads and where it connects, and changed the footers to say where chats go
- Tried it in the site's own container: both of its scripts load and the headers block nothing. Its server refuses the local test address and accepts the site's own, which was checked by asking it directly

## 2026-11-12 — The website shows 0.3.6: new recordings and Settings pictures

- The session that built the change view filmed the four flows again with 0.3.6, on the maintainer's screen and with their yes, and drew three Settings pages again. Nothing was put on the screen for the work below
- Cut the header's recordings and the ones under Use cases from the new footage, under new file names. Proofread is in the header again, second of four. Checked on single frames that the chat drawn under the panel changes when a recording pastes
- The filming of Proofread stopped early, so that recording ends on its result and shows no paste. The cut suggested for it froze the pointer on its way across the panel, so it ends a fifth of a second earlier, where the pointer rests on Replace (see KNOWN_ISSUES.md)
- New pictures of the General, Writing and Spending pages on the site, in the documentation and in the README. The documentation shows the marks after a proofread in two pictures, and the writing state with its text at the top
- On a phone the four names under the recording share its width. On the narrowest phones the pause button gives way to them, and a click or a tap on the recording pauses it, on any screen
- Tried in the real container before it went out: nothing blocked, the recordings can be sought, and the pages were looked at 1512, 390 and 320 pixels wide
- Not verified: Safari, Firefox and a real phone, as before

## 2026-11-12 — Proofread shows what it changed, and a short answer starts at the top

- The maintainer asked for a way to see what Proofread changed, with ways to choose from. Drew four in the conversation; they chose two and asked for both, with a choice in Settings (see DECISIONS.md)
- Added `TextChanges`, which compares the person's text and the result word by word on the Mac, and the two ways the panel shows it: At once, the default, and When I ask. The choice is in Settings, under General. The documentation and the README describe both
- 30 new tests. The whole suite of 399 tests passes and the app builds
- The maintainer said to merge and release. Brought `main` up to the branch by fast-forward, which closed pull request 14, and published 0.3.6 from a tag on `main`. All three release jobs passed, and the release checks out from the outside: notarized, signed by the same Developer ID team, version 0.3.6 with build 3006, the update key the installed copy carries, and a feed and download whose signatures match it
- With the maintainer's yes, filmed the four flows again on their screen, in one run of about a minute, so the website shows 0.3.6. The recordings show the marks after a proofread, and the text at the top of its box while it is written, on the real panel. Its Proofread recording stopped after 8.2 seconds for a reason not found, and it was not filmed again
- The maintainer noticed, in the app and in the site's recordings, that while Claude writes a short answer sits at the bottom of its box and jumps to the top when it is done. The box keeps the newest words in view, and lined a text shorter than itself up with its bottom. The text now fills the box from the top. Measured off the screen in the scroll view itself: one line used to start 37 points down an 84-point box and now starts at the top, and a text longer than the box still opens at its newest words
- Not verified: the real panel with the marks, on screen (see KNOWN_ISSUES.md)

## 2026-11-12 — 0.3.5 released, and the website rebuilt in light and glass

- The maintainer read the night's report and said to merge and release. Brought `main` up to the branch by fast-forward, which closed pull request 13, and published 0.3.5 from a tag on `main`. All three release jobs passed, and the release checks out from the outside: notarized, signed by the same Developer ID team, version 0.3.5 with build 3005, the update key the installed copy carries, and a feed and download whose signatures match that key. The public feed names 0.3.5
- The maintainer turned down the dark website and its header, and asked for a light page with more glass and a video or animations on the right of the header. Both pages have a new look: light, with colour fixed behind sheets of glass (see DECISIONS.md)
- The header now plays three recordings of the real panel, cut close from the raw footage, with the chat they act on drawn under them. Checked on single frames that the drawn text changes when the recording pastes
- Looked at every section at 1512, 1280, 1040, 768 and 390 pixels wide in a headless browser, and fixed what that showed: a hard edge where the gallery cut off its pictures' shadows, sections of the documentation spaced as widely as the home page's, columns of the speed table touching on a phone, and steps showing through the ring around the How it works picture
- Tried both pages in the real container: its headers block nothing, and the recordings can be sought
- With motion turned off, and without scripts, the header shows a still picture and nothing plays
- Checking the live site showed that every recording came gzipped from the server's proxy, the old ones too, so a request for part of one was answered with the whole file. Safari asks for parts before it plays a video. Turned the proxy's compression off for this app and gave the recordings new addresses; a request for part of one is now answered with that part
- Not verified: Safari, Firefox and a real phone, and how the glass performs on an older Mac. Three pictures still show the app before 0.3.5 (see KNOWN_ISSUES.md)

## 2026-11-12 — A night of checks: prompts measured and rewritten, the site's nginx, the chart labels

Asked for by the maintainer before going to sleep: more tests and improvements, a look at speed, security and stability, and research into competitors and features.

- Built a way to measure prompts: each kind of text asked several times of each model at each quality through the app's own client, every answer graded by checks on its text. The first run of 432 answers found far more wrong than the single run before it: 90 failed a check, and Haiku at Fast, the default, failed 32 of 80
- Tried wordings against it, about 3,800 answers over the night. What was learned: Haiku does not think at Fast, with or without the line that asks for an immediate answer; without thinking it proofreads by copying and then corrects itself in the open ("Wait, I need to correct that"), more often the more rules it is given; and no wording fixed that, only thinking did
- Rewrote the prompts and the request (see DECISIONS.md). The same 17 kinds of text now fail in 4 of 459 answers. On ten kinds never used for tuning, 31 of 80 failed before and 1 of 80 after
- Added `WritingHabits`, which counts a template's casing, full stops and apostrophes, and a language check for Explain, both with tests. Added `LiveWritingTests`, the measurement as a test that only runs with a key
- Fixed the dates under the Spending chart: each is centred under its bar, "29 Nov" is no longer cut off, and the newest month of a long All time view has its label again. Checked by drawing the chart for months of 28 to 31 days and for 6 to 48 months, without a window
- Found the website's container was built on nginx 1.29, a line without updates since April 2026. Moved it to 1.30.6 from the stable line, pinned by digest, tried the container locally, pushed it and saw Coolify deploy it: pages, recordings and headers answer as before
- Stability: the whole suite passes under the thread sanitizer and the address sanitizer with no reports, and 15 runs in a row had no failure. The installed 0.3.4, which had updated itself, sat at 0.0% CPU and 15 MB after an hour and a half
- Speed: a connection to Anthropic takes 0.02 to 0.05 s to set up from here, so opening one ahead of time would gain nothing worth a request nobody asked for. Summing up Spending takes 47 ms for 10,000 requests
- Security: the two cases with orders hidden in the text or the context passed in every run. The dependencies and the workflow actions are pinned to commits. The Keychain item for the API key still lists a debug build from a temporary folder among the apps that may read it; nothing was changed there
- The research report on competitors and features was delivered to the maintainer as a file. It is not in the repository
- Updated the site, the documentation and the README for what Proofread now does
- The test runs of the night cost about $2.50 of the maintainer's API credit
- Requests with a picture attached were asked of the real models for the first time: Explain and Compose both read a drawn conversation, 12 answers of 12
- Not verified: the new prompts with a capture of a real window or with pasted context longer than a line; Proofread on texts longer than 290 words; Settings on macOS 14 and 15; the site in Safari and Firefox

## 2026-11-12 — The models tried through the API, a new website with docs, and a fuller README

- The maintainer entered the Keychain password, and the run of Haiku, Sonnet and Opus at each quality went through: 99 requests through the app's own client, none failed, about $0.20 in all. Haiku gave its first word in 0.6 seconds and a whole answer in 1.0, for about $0.0001 a message. Sonnet took 0.7 and 1.4 seconds, Opus 1.1 and 1.8 at Fast
- The answers showed two faults in prompts: at Balanced, Sonnet once wrote its second thoughts into a proofread ("Wait, I need to apply only…"), and at Fast, Haiku opened an explanation with a sentence about which language it would answer in. They also showed Proofread with a style leaving out apostrophes the style's messages use
- Filmed the real panel over a made-up desktop: four clips (rewrite, proofread, explain, compose) and stills of each screen, plus pictures of every Settings page in both themes. A leftover Keychain dialog and the real pointer were kept out of the pictures by moving the scene
- Built the website twice. The maintainer turned the first design down as dated. The second is dark and typographic, with the recordings, tiles of small demos, a copy of the panel that runs in the browser and a documentation page for every screen and button
- Deployed it to the maintainer's Coolify server at oman-ai.romanbitca.com. The container was built and tried locally first. Live: both pages and the recordings load, plain HTTP redirects, the security headers are there
- Rewrote the README with a recording, pictures, the measured model table and links to the site and docs
- Started research into competitors and features worth building
- Not verified: the site in Safari and Firefox; the page's own request to GitHub from the live site, because this address had used up GitHub's hourly allowance and the page showed its fallback text

## 2026-11-11 — Settings rebuilt in macOS's own design, spending by period, the on-device model tried

- The maintainer chose tabs in the toolbar with native controls, the single-wave icon and the name As written. They also asked for a divider and one scrolling line of templates, a Screen chip without a button of its own, a more advanced Spending page, and a test of the models, the on-device one above all
- Panel: As written, a thin divider, then the templates on one line that scrolls under a fade and opens at the chosen one. The picture under the Screen chip lost its remove button. In the preview that button had shown alone, because the preview's made-up picture couldn't be decoded
- Menu bar icon: one wave as a single stroke
- Settings: rebuilt as a toolbar-tab window of grouped forms. Removed the hand-drawn Settings controls, the glass container, the motion switch and the wrapping layout, which nothing uses now
- Spending: one period control for today, this week, this month, last month and all time, with the total, requests, tokens, the average, a chart by hour, day or month, and a list by model
- Apple's model runs on this Mac. Trying it found that this morning's prompt made it proofread in capitals; fixed before any release. Compared it with Haiku on eleven tasks
- Left a sheet opening and closing on the maintainer's screen for about twenty minutes: the preview script closed a SwiftUI sheet from outside in a loop, and SwiftUI kept reopening it. They ended it by pressing Done. One more run then showed on screen although it was placed off it. After that the test window was kept off every display and drew itself to a file
- Verified: 336 tests pass and the app builds. Every Settings page was captured on screen in light and dark before the Spending page changed, and the style sheet in both themes. The new Spending page was drawn off-screen for Today, Last month and All time
- Not verified: the delete alert by hand; Settings on macOS 14 and 15; the Claude models at each quality through the API; the installed app
- A Settings window low on the display now moves up when a taller page would reach below it. 339 tests pass
- The maintainer asked to publish. Published 0.3.4 from a tag on `main`. All three release jobs passed, and the release checks out from the outside: notarized, signed by the same team, version 0.3.4 with build 3004, a signed feed whose signature and length match the download
- The run of Haiku, Sonnet and Opus through the API was started twice and never began: reading the key from the Keychain needs the maintainer's password, and they were away. The command is ready for them to run

## 2026-11-11 — Panel position, templates and context as choices, proposals for Settings and the icon

- The maintainer liked 0.3.3 and asked for four things: the panel a little lower, templates and context chips that only choose, a better Settings screen in macOS's own style, and a better menu bar icon, with ideas shown before the last two are built
- The panel sat 1.5 points under the menu bar: it hung from the icon's own box, which ends 6 points above the bar's edge. Control Center's first module starts 12 points below the bar. The window now hangs from the bar's edge with that gap inside it, and a capture reads the first tile at the same height as Control Center's module
- Template chips choose and start nothing, with the person's own voice first (named As written later the same day). Proofread now follows the chosen template's habits, Rewrite without a template keeps the writer's voice, and the last template is remembered when used. Screen, Messages and Clipboard are switches; the clipboard's text is shown when it is on
- Left Control Center open on the maintainer's screen for a few minutes: two captures of it failed to save, which left its toggle one press out of step. Closed it, and added a check that says whether it is open
- Built two Settings prototypes with macOS's own controls, a sidebar as in System Settings and tabs in the toolbar as in Safari, captured beside the present design, and drew eight menu bar icon ideas. Nothing of these is in the app yet
- Verified: 329 tests pass and the app builds. Captured the new chips on screen with one template chosen, and with Messages and Clipboard on together
- Not verified: how Proofread with a template reads against the live API; the installed app. Not released

## 2026-11-11 — Lag found and fixed, a fading backdrop, faster screen changes

- The maintainer tried the preview: it looked better, but a click made it lag, the blur began at a visible straight line, and the animation after a click should be very fast and smooth
- The lag in the preview was the preview: its process was stuck in AppKit's Password AutoFill check, which the app switches off and the preview did not. That freeze can now be reproduced on demand, and the app's guard was checked against it for the first time. The preview also never let an answer arrive, so it stayed on the writing screen
- Measuring the panel properly then found two real causes of lag, both older than 0.3.0. The writing glow kept the main thread 99% busy, and screen changes ran at 34 frames a second because of Apple's glass container
- Took the tiles out of the container and matched them between screens instead: 111 to 119 frames a second. Made the content swap faster than the tiles move, after slow-motion captures showed two screens readable at once. Rebuilt the glow as a turning Core Animation layer: 1% of a core
- Rebuilt the backdrop as one window with Core Animation's backdrop layer and a blur that varies in strength, so it fades instead of beginning in steps, and fades in when the panel opens. On a finer checkerboard its fade outside the tiles reads 0.6 and 1.0 points where Control Center's reads 0.5 and 1.0, and 3.0 points behind the tiles
- The panel now arrives with a fade and a short drop from the menu bar, at 120 frames a second. Growing into place ran at 60 and was dropped. Closing is unchanged
- Verified: 318 tests pass and the app builds. In an optimised build on a 120 Hz display: still screens use 1% of the main thread, the writing screen 1%, screen changes hold 111 to 117 frames a second, opening holds 120. Tiles read the same against Control Center as before, on seven fields. The pinned panel and the Light theme look as before
- Not verified: the installed app, since only the preview panel was measured; a display with one pixel per point; macOS 26; how it feels by hand. Each screen change still starts with one stall of 30 to 55 ms while the new screen is built, and the first use of a screen after launch takes between a tenth and a third of a second. Not released
- The preview first stopped by itself on the maintainer's clicks: its waiting loop gave its turn back to the process's outermost run loop, which AppKit stops when an event arrives, so the process exited as if finished. Run from a run-loop block instead, it held through 90 seconds of real clicks
- The maintainer tried that preview, said it looked fine and asked to deploy. Published 0.3.3 from a tag on `main`, with this entry's work and the tile colour and focus changes below, and the release's test step standing in for the pull request's check again. All three release jobs passed. Checked from outside: Gatekeeper accepts it as notarized Developer ID, it is version 0.3.3 (3003), the zip's signature verifies with the update key built into the app, and the public feed serves 0.3.3. The installed copy was still 0.3.2 when this was written

## 2026-11-11 — Tile colour and focus matched to Control Center

- The maintainer liked the measured backdrop, but found the tiles too dark and not glassy enough next to Control Center, and noticed the panel turning darker when it lost focus
- Measured Control Center's tiles on plain colour fields. Brightness follows the law found on grays, and colours come out about 1.25 times more vivid than what is behind the tile. Ours cut colour by a third, because of the gray layer over the glass
- Tried eight ways to shade the glass in a lab window and scored each against Control Center on seven fields. A shade that changes brightness only, plus a saturation boost of 1.25, came closest: 17 levels of error in total over 21 readings, against 88 for that shade alone and 147 for the gray layer used before
- In the real panel the boost did nothing at first, because the tiles share a glass container that draws their glass. Moved it to the whole panel. The app's icon and the screenshot preview undo it. A second way, a dodge blend on each tile, scored 97 or worse
- Glass in a window that isn't key is drawn darker and flat. SwiftUI's environment switches didn't change that. Answering `hasKeyAppearance` from the panel's window did: a capture of the panel after it lost the keyboard reads the same as the focused one, and the Write button keeps its colour
- Verified: 317 tests pass and the app builds. Through a tile the panel is within 4 levels in 100 of Control Center on all seven fields, and reads the same on dark grays. The app icon's colours are unchanged, and the pinned panel and the Light theme look as before. Captured next to Control Center over a colour gradient, a white page, a dark page and the desktop
- Not verified: the installed app, since only the preview panel was captured; the look while text streams in; whether a boost over the whole panel costs anything while it animates; the colour of selected text in a pinned panel that isn't focused. Not released

## 2026-11-11 — Backdrop rebuilt from measurements of Control Center

- The maintainer rejected the blurred card behind the panel as a box that was not really transparent, and a wider band of glass because it blurred everything. Stopped judging by eye: put a checkerboard behind the real Control Center and read its blur and tone square by square
- Found a slight, local effect with no tint: 3 points of blur and 10% darkening, fading within about 40 and 126 points of the modules. Every earlier version blurred several times more and tinted what it blurred
- Rebuilt the backdrop on the window server's blur, in six nested windows plus one for the darkening, and tuned the tiles to Control Center's tone. On the same checkerboard ours reads 2.8 to 3.1 points of blur, 90% white, and 73% and 13% through a tile, against Control Center's 3.0, 90%, 73% and 13%
- Earlier captures were misleading because the preview window was never the key window, and glass in such a window is drawn flat and gray
- Text to read or type stays on frosted glass. Tiles are 12 points apart with rounder corners
- Verified: 315 tests pass, the app builds, and the backdrop keeps its numbers after the panel closes, reopens and changes height. Captured next to Control Center over a white app, a dark app, a colour gradient and the desktop
- Not verified: the real app with the new backdrop, since only the preview panel was captured, and how it looks while text streams in. Not released: using the private call is the maintainer's decision

## 2026-11-11 — Panel matched against Control Center on screen

- The maintainer found 0.3.2 still looked bad next to Control Center and asked for the closest match, compared on several backgrounds
- With the maintainer's permission, built a temporary preview that showed the panel and the real Control Center in the top-right corner over a white app, a dark app, a bright gradient and the desktop, and captured each. Nothing was committed from it
- What the comparison settled: clear glass tiles; the style and context chips grouped in one tile with flat chips, solid white when on; a soft blur built into the panel's window behind and around the tiles, which closes the panel when clicked; disabled buttons dim only their label. The halo's mask had its fade inside the tiles at first, found by its tests and fixed
- Remaining gap: over a dark app in light mode the blur is a light frosted card, because macOS has no public pure blur. Recorded in KNOWN_ISSUES.md
- Verified: 313 tests pass, including where clicks land around the halo, and the app builds. Not verified: the panel in daily use with the halo, such as clicking just beside it

## 2026-11-11 — Backdrop removed

- The maintainer installed 0.3.1 and sent screenshots with the panel open and closed: the backdrop grayed out half the screen without blurring it, and clear glass showed the app's text through the tiles. It looked very bad
- Removed the backdrop window and clear glass. Tiles are frosted glass again; the dark panel with white text, interactive glass buttons and white "on" chips stay
- Verified: 305 tests pass and the app builds. Not verified: how it looks on screen
- Published 0.3.2 from a tag on `main`, with the release's test step standing in for the pull request's check again. All three release jobs passed; the command waiting on them lost its connection to GitHub, which looked like a failure until the run was read. Checked from outside: Gatekeeper accepts it as notarized Developer ID, it is version 0.3.2 (3002), and the zip's and the feed's signatures verify with the update key inside the installed app. The maintainer's Mac had already updated itself to 0.3.2

## 2026-11-11 — Control Center look for the panel

- The maintainer compared the panel with Control Center and asked for the native look, including Apple's glass buttons that flex when pressed
- Added a click-through backdrop window that dims and slightly blurs the side of the screen behind the panel and fades out beyond it, hidden while the panel is pinned. The panel is dark with white text when the theme is Match system, its tiles are clear glass over the backdrop, its buttons use interactive glass, and chosen chips are white instead of purple. Settings is unchanged
- The rules for which glass a shape gets and where the backdrop goes are plain code with tests. 310 tests pass and the app builds without warnings
- Not verified: how any of it looks, because glass and behind-window blur don't render offscreen; that clicks still land on clear glass, which has the 2% fill as a precaution; and how strong the dim and blur feel. The maintainer reviews it on screen
- Published 0.3.1, with this and the Writing Tools fix, from a tag on `main`. The pull request's own check was still running when `main` moved, so the release's test step stood in for it, and all three release jobs passed. Checked from outside: Gatekeeper accepts it as notarized Developer ID, it is version 0.3.1 (3001), the zip's and the feed's signatures verify with the update key inside the installed 0.3.0, and the public feed serves 0.3.1

## 2026-11-11 — Back covered by Apple's Writing Tools

- The maintainer tried 0.3.0: Explain worked against the live API, but Back sometimes did nothing and the app sometimes felt slow
- Read the system log of the installed app instead of driving the screen. No hang or unresponsive report. Apple's Writing Tools set up its floating button and host window inside OmanAI's panel seconds before the failed Back, and it had done so in 0.2.1 too
- Turned Writing Tools off for OmanAI's own text in the panel and Settings. A new test checks that the panel's text views and a one-line field's editor report it off; the field's editor reported "limited" before
- Back now writes the screen it went to in the system log, without any text
- Verified: 302 tests pass and the app builds. Not verified: Back on screen after the change, and the cause of the slowness

## 2026-11-11 — Explain, smaller buttons and spending

- Added Explain to the panel: it reads the selected text as its recipient would and says what they will understand, how it sounds and what could be misread. It uses the conversation's context, has its own short system prompt and an assignable shortcut, and its result can be copied but never pasted
- Proofread, Rewrite and Explain are now one row of 40-point capsule buttons instead of two 80-point cards
- Added a Spending page to Settings with totals for today and this week and bar charts for the last 14 days and 8 weeks. Each Claude request now records its token counts in a new `api_usage` table, priced with Anthropic's list prices from 2026-11-11. No text is stored
- Verified: 301 tests pass, 30 of them new, and the app builds. Token counts are read separately from the stop reason, so a change in how Anthropic reports usage can't make answers look cut off. Offscreen renders checked the button row, the explanation screen and the Spending page in light and dark, with real charts. Glass doesn't render offscreen, so the buttons' shapes were measured instead: the widest label needs 104 of its 115 points
- Not verified: Explain against the live API, which needs a few real requests with the maintainer's key, and the new buttons as glass on screen. The costs are checked against hand-worked figures, not against a real Anthropic bill
- Removed this session's leftover build copies from LaunchServices. Only `/Applications/OmanAI.app` and an older copy in the Trash are still registered
- Published 0.3.0 from a tag on `main`, after CI passed on pull request #7. All three release jobs passed. Checked from outside: Gatekeeper accepts it as notarized Developer ID with the ticket stapled, Sparkle's helpers are signed by the same team, it is version 0.3.0 (3000), the zip's and the feed's signatures both verify with the update key inside the installed 0.2.1, and the public feed address serves 0.3.0. Not checked: the update itself on the maintainer's Mac

## 2026-11-11 — Security review and fixes

- Reviewed what leaves the Mac, the clipboard handling, the API key, prompt injection, the two permissions, Sparkle updates, the release pipeline and the repository's history, then fixed what the review found. The choices made are in DECISIONS.md
- Panel and API: prompt tags that selected or pasted text can't forge, cut-off responses no longer accepted as finished, hidden context no longer sent unseen, an uncropped screenshot preview, requests that wait for the screen capture, results cleaned of hidden characters, the clipboard read only on request, and smaller fixes
- Clipboard and paste: `ClipboardRoute` gives the clipboard back when the app has read the paste and undoes a copy that arrives late. No synthetic ⌘C for terminals, remote desktops and virtual machines. Insert checks where the cursor is, and terminals need a second press
- Releases: the workflow is split into check, build and publish, with secrets in an approved `release` environment. Sparkle now requires a signed feed and checks an update before unpacking it. GRDB, Sparkle and XcodeGen are pinned. docs/RELEASING.md describes the new setup
- Verified: 266 tests pass, and passed 20 runs in a row, half of them with every CPU core busy. The app builds. A throwaway Release build and a throwaway key showed that the feed tool signs the feed once the app asks for it, and both signatures checked out independently. Lazy pasteboard delivery was checked between two processes on a private pasteboard
- Not verified: capture and paste in real apps with the new clipboard code, which needs an on-screen test. The new prompt format against the live API, which needs a few real rewrites. The workflows and `setup-release-secrets.sh`, which have not run since they changed. A real update from 0.2.0
- A second review of the merged changes found ten more points. Fixed: overlapping clipboard operations, a black flag emoji that could hide text, a saved key that macOS won't hand over being reported as missing, a fragile check in the setup script, and two duplicated helpers. `Package.resolved` turned out to be rewritten by Xcode as well as by `swift test`, so it is no longer committed. 271 tests pass
- Added the tag and `main` rulesets on GitHub, and a landing page in `site/` with a demo of the panel that visitors can try. Checked at desktop and phone widths in light and dark. It is not hosted anywhere yet
- Published 0.2.1 from a tag on `main`, with everything above. It was the first run of the reworked release workflow, and all three jobs passed: the tests, a notarized build, and a release with a signed feed. Checked from outside: the feed's signature is valid for the update key inside an installed 0.2.0, the feed's length matches the zip on GitHub, the address the app asks serves that feed, and the build log shows the same update key going into 0.2.1. Not checked: the zip's own signature, which the app checks itself when it updates. The run asked for no approval, see KNOWN_ISSUES.md
- The maintainer updated an installed 0.2.0 to 0.2.1 from inside the app, the first real update through Sparkle. Read from the installed copy afterwards: version 0.2.1 (2001), the same Developer ID team, a valid signature with the notarization ticket stapled, both new update checks on, and the same update key. The app only installs a zip whose signature it has checked, so the zip's signature is settled too
- The maintainer then tried 0.2.1 and reported that everything seems to work, which covers the Accessibility permission carrying over. With that, every acceptance point of W7 is met, and PLAN.md marks it done. W1 to W6 stay in progress until the maintainer signs off on their acceptance lists
- Next for the maintainer: choose where to host the landing page, and run `mac/scripts/setup-release-secrets.sh` so that a release asks for approval (see KNOWN_ISSUES.md)

## 2026-11-10 — Pivot to a menu bar writing tool, native Swift build

- Direction changed: writing tool first, meeting recorder parked. Decisions recorded in DECISIONS.md, phases W1 to W5 added to PLAN.md, CLAUDE.md and README.md updated
- Built in `mac/`: `OmanKit` package (OmanCore contract, ClaudeAPI, OmanStorage, SystemBridge, OmanUI) and the app shell (status item, non-activating panel, Settings window). The four modules were built in parallel by subagents against one shared contract, then reviewed and merged
- Haiku 5.5 is the default model, with Sonnet 5.5 and Opus 5.5 in Settings. Actions are Proofread, Rewrite, styles, free-text instruction and Compose
- Verified: 145 tests pass; the signed app builds and runs at a 28 MB footprint; scripted clicks on the icon open and close the panel under it while the frontmost app stays frontmost; every screen and both Settings tabs were checked in offscreen renders
- Not verified yet, because it needs the user's Accessibility grant and API key: selection capture and paste in real apps, typing in the panel, a live Claude request, real mouse clicks on the icon. W1 to W5 stay [IN PROGRESS] until those pass
- Fixed after the user's first try: Cmd+V did nothing in text fields, because a menu-bar-only app has no Edit menu. Added one for the Settings window, and direct handling of editing shortcuts in the non-activating panel, including non-Latin keyboard layouts
- oman did not appear in the Accessibility list because the build ran from a temporary folder. Installed a signed Release build to `/Applications/oman.app`
- Liquid Glass pass: the panel is now floating glass tiles in a fixed transparent window so shapes can morph, and Settings moved to a sidebar. Minimum OS stays macOS 14 with a material fallback. Layout checked offscreen and 145 tests pass, but real glass rendering has not been seen, because this session has no Screen Recording permission. The user is taking the design to Claude Design
- Signing: no Developer ID certificate on this Mac. The only paid team in Xcode belonged to a different account, and Xcode's login for it was rejected. The user needs to confirm which account signs
- The user likes the panel's look. Fixed a freeze: the main thread spun at 100% inside AppKit's Password AutoFill heuristics, which also made buttons look dead. Could not reproduce it on demand, so the fix (AutoFill heuristics off, confirmed idle afterwards) still needs real use to confirm
- Added assignable shortcuts (global, per style, and for results), redesigned Settings with new options (theme, quality, language, standing rules, default style, panel defaults), a pinned panel as a draggable floating window, and Apple's on-device model. 194 tests pass; the on-device model ran for real on this Mac. Real key presses for global shortcuts, dragging, and the look of the new Settings are not verified by me
- Second design pass from the user's feedback: curved drag grip at the panel's top-right corner, an opaque draggable Settings window, no bouncing motion. Installed the flow icon and menu bar glyph
- Signing: Developer ID works with the personal Apple Developer account (team S72639F3BR). Added `mac/scripts/release.sh` for sign and notarize
- First notarized build: Gatekeeper reports `Notarized Developer ID`, the ticket is stapled, and it is installed in `/Applications`. The signature changed, so Accessibility has to be allowed again. Selection reading and paste have not been re-tested on this build
- The app is now named OmanAI. The bundle ID, Keychain service and database folder did not change, so saved styles and the API key carry over
- Third design pass: the pinned panel's grip is a dark curve with a thin glass border, and Settings has no animation at all, including a hand-drawn switch. The first curved grip could not drag for two reasons, both found with real mouse events: shapes above the drag area took the click, and Liquid Glass in a custom shape counts as clear to the window server. Real drags moved the installed panel from the middle and both ends of the curve. The final build only removed an extra grab area that did not catch clicks
- Accessibility has been refused since the move from the Apple Development build to Developer ID, because the existing grant is tied to the old signature. It needs the user to remove OmanAI from the list and allow it again. Selection reading and paste still need re-testing on the Developer ID build, and the new Settings has been checked offscreen only
- Prepared the project for open source and automatic updates: MIT license, public README and contributor files, GitHub Actions for tests and for signed releases from a tag, Sparkle updates from GitHub Releases, an ad hoc default build, and the meeting recorder moved to an archive branch
- Published the repo and released `v0.2.0` through GitHub Actions. Verified: 200 tests pass locally and on GitHub, an ad hoc build works with no Apple account, the published app passes Gatekeeper as notarized Developer ID with Sparkle's helpers signed, and the feed's signature matches the key built into the app. Not verified: no installed app has updated itself yet, because 0.1.0 has no updater and the first real test needs a later release
- Next: a test and security review, the bug pass, and the landing page

## 2026-04-28 — Project bootstrap

- Repo created at github.com/romanbitca/oman-ai
- Created README.md, CLAUDE.md, PLAN.md, DECISIONS.md, KNOWN_ISSUES.md, SESSION_LOG.md
- Stack and v1 scope locked
- Next: run Phase 1 (Skeleton) with Claude Code

## 2026-04-29 — P2 verified by user

- Confirmed on user's Mac: app launches, `personal.db` auto-created at correct path, workspace switcher works, creating new workspaces produces new `.db` files, all schema tables present, settings seeded correctly, typecheck and lint pass, no console errors
- P2 closed. Next: P3 — Mac audio recording

## 2026-04-28 — P2 SQLite + workspaces implemented

- `better-sqlite3` 11.5 + `@types/better-sqlite3` installed; native module rebuilt for Electron 33's arm64 ABI via `electron-builder install-app-deps` (added as `postinstall` script so future installs stay correct)
- Workspace files at `~/Library/Application Support/oman/workspaces/{slug}.db` (Mac) — uses `app.getPath('userData')`; same code maps to `%APPDATA%/oman/workspaces/{slug}.db` on Windows
- `electron/services/migrations.ts`: schema-V1 SQL block (all 7 tables incl. `meetings_fts` FTS5), `applyMigrations` keyed by `PRAGMA user_version` and wrapped per-step in a transaction; `seedSettings` writes the three seed rows with `INSERT OR IGNORE`
- `electron/services/workspace-manager.ts`: `listWorkspaces`, `getCurrentWorkspace`, `switchWorkspace`, `createWorkspace`, `deleteWorkspace`, `initWorkspaces`, `closeCurrent`. WAL journal mode enabled. `slugify()` normalises display name to filesystem-safe slug
- `electron/ipc.ts`: four `ipcMain.handle` channels (`workspace:list|current|create|switch`); create auto-switches
- `electron/preload.ts`: exposes typed `omanApi.workspaces.{list,current,create,switch}` via `contextBridge`
- `electron/main.ts`: `initWorkspaces()` + `registerIpc()` on `app.whenReady`; `closeCurrent()` on `before-quit`
- `shared/types.ts`: `WorkspaceMeta`, `OmanApi`, and `Window.omanApi` global declaration
- `src/store/workspace-store.ts`: Zustand store with `current`, `workspaces`, `ready`, `load`, `switchTo`, `create`
- `src/components/workspace-switcher.tsx`: top-left dropdown button — shows current slug, lists all workspaces, inline "+ New workspace" form (Enter to submit, Escape to cancel, click-outside to close); displays IPC errors inline
- `src/App.tsx`: header bar with switcher; "oman" remains in main panel
- Verified end-to-end: clean userData dir → `npm run dev` auto-creates `personal.db`; sqlite3 confirms 7 spec tables + FTS5 internals + seeded settings (`transcription_mode=local`, `anthropic_api_key=NULL`, `drive_upload=false`) + `user_version=1`. An env-gated routine in main.ts (added then reverted) exercised create/switch/switch-back; user separately drove the UI to create a `t` workspace, confirming the full renderer→IPC→manager path
- `npm run typecheck`, `npm run lint`, `npm run build`, `npm run dev` all clean
- Next: P3 — Mac audio recording

## 2026-04-28 — P1 Skeleton implemented

- electron-vite + electron-builder wired up; main in `electron/`, preload at `electron/preload.ts`, renderer in `src/`
- TypeScript strict mode, project references (`tsconfig.node.json` for main/preload, `tsconfig.web.json` for renderer)
- Path aliases configured in both tsconfig and electron.vite.config.ts: `@/` → `src/`, `@shared/` → `shared/`, `@electron/` → `electron/`
- Tailwind 3 with `darkMode: 'class'`; `class="dark"` set on `<html>` so dark is the default theme
- shadcn/ui initialized via `components.json` (neutral base, CSS variables); `cn` helper at `src/lib/utils.ts`; full neutral color tokens in `src/globals.css`. No components added yet (none needed for P1)
- Zustand installed but unused yet; reserved for P2
- Scripts: `dev`, `build`, `dist:mac`, `dist:win`, `typecheck`, `lint`, `format`
- `electron-builder.yml`: dmg (arm64+x64) + nsis (x64), GitHub publish target, `mac.identity: null` for unsigned local dist (P12 will revisit)
- System tray with placeholder 22×22 PNG (`resources/tray-icon.png`); macOS template-image flag for menu-bar dark/light auto-invert. Click toggles main window; right-click shows Show/Hide + Quit
- Main window 1200×800, min 900×600, dark backgroundColor, autoHideMenuBar
- Empty React app shows "oman" centered (`src/App.tsx`)
- ESLint 8 + Prettier; rules forbid `any`, ignore underscore-prefixed unused vars
- Verified: `npm run typecheck` passes, `npm run lint` passes, `npm run build` produces `out/{main,preload,renderer}` cleanly, `npm run dev` launches Electron and main window with no console errors
- Gotcha discovered: `sandbox: true` + ESM preload fails silently. Documented in KNOWN_ISSUES.md; using `sandbox: false` for now
- P1 verified working on user's Mac: window opens, tray icon renders and toggles the window, no console errors
- 7 implementation decisions formalized in DECISIONS.md (sandbox flag, app ID, mac identity, tailwind/eslint versions, tray template image, window-close behavior, external link handling)
- Next: P2 — SQLite + workspaces
