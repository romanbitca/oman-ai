# Known Issues

Active bugs, gotchas, and workarounds. Append entries with date.

---

## 2026-11-12 — Words that wait for a field: what has been tried, and what hasn't

Tried: tests for each answer, a paste when a field gets the cursor with the space after and Return, Copy, ×, the minute, and opening the panel or starting a dictation meanwhile; and the rules for each role. What apps answer was read, without changing anything, from the apps open on this Mac while it was locked, so every one answered as an app in the background: Slack and the other Electron apps said nothing had focus, and so did Mail; Notes, Telegram, WhatsApp and Messages named the app itself, and the Finder named its desktop, a group with the subrole AXDesktop and a text range. Messages didn't answer within the 0.25 seconds the first time it was asked, which counts as can't be told. The app's own reader, built on its own, sorted them as the rules say: the Electron apps can't be told, the desktop takes no text. Asking an app took 20 to 130 milliseconds.

In 0.4.2 the maintainer met the first limit below: words dictated with the Finder in front waited, and a click into an Electron app's message field didn't take them. With the Mac in use, a Chromium browser in front also answered that nothing had focus. Paste in the pill came from that.

Then, with the maintainer clicking into each app's field and a reader built from the app's own code noting only roles, what apps answer while they are in front: a mail being written in Mail is a page whose value can be set, and its To and Subject are text fields, so they take text; a mail being read is a page that can't be set, so it takes none; the message fields of Telegram and WhatsApp are text areas, so they take text; Slack and other Electron apps said nothing had focus, so they can't be told. Neither Telegram nor WhatsApp named the app itself in front. WhatsApp's window with no field in focus named a group of its own (subrole iOSContentGroup), which can't be told, and right after each switch WhatsApp and Telegram didn't answer for a moment, which can't be told either.

A second run switched on the accessibility support of each app in front that said nothing had focus, and back off at the end. Slack and two other Electron apps then named their message field, a text area, within about three seconds, and Arc did too. Chrome and another Chromium browser refused the switch, so fields inside their pages still can't be told; Chrome's own address bar is a text field either way. Safari, Notes and Messages named their fields without it, so Messages doesn't name the app itself in front either. That run led to switching it on while words wait.

Not yet tried:

- Paste on the screen. Its click shouldn't move the keyboard, as Done's doesn't, but that has only been reasoned, not seen
- The switch inside the app itself: the runs above used a separate reader, built from the app's code
- A Finder window in icon view, and a page in Safari with no field in focus
- macOS before 27, where the desktop may answer differently

Known limits:

- An Electron app takes up to about three seconds after its support is switched on to name the field clicked, and may run a little slower until the wait ends
- Chrome and other Chromium browsers refuse the switch, and Arc's can't be read, so OmanAI leaves it alone: in their pages waiting words don't go in by themselves when a field is clicked, and Paste puts them there
- If OmanAI quits while words wait, an app it switched on keeps its accessibility support on until that app quits
- A dictation made in an app that can't say goes in as before, so where nothing there takes text it is still pasted into nowhere and kept only in Transcripts and Copy last transcript
- Something with a role OmanAI doesn't know counts as can't be told, and is pasted into as before. A Finder window in icon view may be one
- Escape stays taken while words wait, for up to a minute, so it doesn't reach the app in front meanwhile. Its first press throws the words away; their transcript stays
- Waiting words go into whatever field gets the cursor next, even one clicked for something else, such as a search field

---

## 2026-11-13 — The website's recordings and pictures for 0.4.5

With the maintainer's yes, one filming run on their screen, 167 seconds in all, filmed every recording again with 0.4.5: Rewrite, Proofread, Explain and Compose, and three dictations. Settings showed on the screen for ten of those seconds, for its Dictation and Shortcuts pages. Nothing outside the test's own windows was clicked or typed. Before it, the clicks each film makes were checked off every display: the Work chip, Rewrite, Insert and the pill's ✨ each did what the film needs.

- Proofread now ends with its paste, which the 0.3.6 recording never reached, so its header clip changes the chat at 12.60 seconds like the others
- Each film ends where its test ends. The explanation and the dictation are held at their last picture for a few seconds, so they can be read
- OmanAI's window is drawn off the screen, with four months of made-up use and in UK English, so numbers read 1,033 and times 9:40. It is never filled from the maintainer's own transcripts
- The panel pictures in the docs come from the same run, and show the panel without its old gear

What is still not as it should be:

- The pictures of Styles, the style editor, Writing, General, Spending and Key & Permissions are from 0.3.4 to 0.3.6. Those pages have not changed since
- `og.png`, the picture shown when the site is shared, is older still
- On a phone 390 points wide the page is 2 points wider than the screen, because of the glow behind the header's recordings. That was so before this update
- Checked in Chromium only, at 1440 and 390 points wide

---

## 2026-11-13 — Transcript times wrap with a 12-hour clock

In OmanAI's window each transcript's time sat in a column 44 points wide (`HomeTranscripts.swift`). With a 24-hour clock "9:40" fits. With a 12-hour clock, as in US English, "9:12 AM" broke onto two lines. Seen in a picture of the window drawn with US English.

Fixed after 0.4.5: the column is as wide as the longest time the clock writes in the Mac's region, such as "12:58 PM", measured in the label's own font, and never under 44 points. Drawn again in US English, every time fits on one line and the transcripts start in one column. Worked out once for each region and hour cycle, so a clock changed while OmanAI runs gets its width too.

---

## 2026-11-13 — The Floating look's background: what has been tried

The maintainer found the darkening behind the Floating look's words too easy to notice, asked for variants, and then left the choice to the assistant. White words need something dark behind them only where the screen is bright. The even darkening of 0.4.4 showed as a dark cloud over a mid-toned desktop picture, where it isn't needed, and was still too faint over a white window.

Tried:
- Five variants drawn as simulated pictures in a headless browser, over the maintainer's desktop picture, a white window of text and a dark one. The browser's blur and curve only stood in for Core Animation's.
- With the maintainer's yes, while they were away and the Mac was unlocked: five short runs of a test window on their screen, 84 seconds in all. Four showed the Floating look's words over a sheet of white text, a sheet of dark text and the desktop, beside the same background with no words, and saved a picture of each; two measured the filters on grey bars from black to white. Nothing was clicked or typed, and nothing was left on the screen. The first run's pictures of the bare desktop held the windows open on it, so they were deleted and the later runs showed a copy of the desktop picture instead.
- On the grey bars, `luminanceCurveMap` and `curves` both draw a cubic Bézier through the four values they are given: with 0, ⅓, ⅔ and w, a brightness of x comes out as x − (1 − w)x³. The values first guessed darkened mid-greys about as much as white.
- `luminanceCurveMap` works on brightness alone, so over the desktop picture it left a grey patch where there had been colour. `curves` takes the same values for each colour and keeps them.
- As a second filter on the blur's own layer, the curve needed that layer faded as a whole, and the blur then faded twice as fast. In a layer of its own under the blur, the blur takes in what the curve darkened.
- Every variant measured behind the words: the average brightness from 0 to 1, and the contrast of white words against it. Contrast of the average leaves out the letters' own shadow, which adds to it.

| Behind the words | Desktop picture | White window | Dark window |
| --- | --- | --- | --- |
| Nothing | 0.635, 2.5:1 | 0.838, 1.5:1 | 0.269, 9.7:1 |
| 0.4.4: everything darkened by 0.24 | 0.482, 4.2:1 | 0.673, 2.3:1 | 0.169, 14.2:1 |
| Half that | not measured | 0.776, 1.7:1 | 0.196, 12.8:1 |
| Everything darkened by 0.16, with more shadow on the letters | 0.531, 3.6:1 | 0.744, 1.9:1 | 0.188, 13.2:1 |
| Brightness alone, white to 0.55, under the blur | 0.530, 3.6:1 | 0.547, 3.4:1 | 0.196, 12.8:1 |
| Brightness alone, white to 0.45, under the blur | 0.509, 3.9:1 | 0.473, 4.4:1 | 0.188, 13.2:1 |
| Each colour, white to 0.55, on the blur's own layer, wider | 0.519, 3.7:1 | 0.573, 3.1:1 | 0.220, 11.7:1 |
| **0.4.5: each colour, white to 0.55, under the blur** | **0.532, 3.6:1** | **0.547, 3.4:1** | **0.196, 12.8:1** |

Not yet tried:
- The look in the app itself, rather than in a test window built from the same code.
- macOS before 27.

Known limits:
- `curves` is a private Core Animation filter, as the blur is. Where a macOS doesn't have it, the even darkening of 0.4.4 stands in, and either could go in a later macOS.
- Over a white window 0.4.5 is darker behind the words than 0.4.4 was, on purpose: white words there went from 2.3:1 to 3.4:1.
- Light greys come out a little lighter than white, since the curve bends back: 0.86 comes out as 0.57 and white as 0.55. The blur hides it.

## 2026-11-12 — OmanAI's window, keys held together and the pill's new look: what has been tried

Tried:
- Tests for the chord tracker: one key, two keys in either order, a chord growing into another, other keys, Shift and Fn, and keys that can't make a chord.
- Tests for recording and saving chords, single keys saved by 0.4.2 still loading, and dictating with two keys held.
- Tests for the window's numbers: each stretch, speed, pages and time saved, the line's steps, the streak, fixes by kind, how the writing goes, the apps, the year map and its shades, and which tiles show for someone new, someone who only dictates, only writes, or does both.
- Tests for counting a dictation without its words, with transcripts kept and not kept, for deleting transcripts leaving the counts, and for a database from 0.4.3 being counted once.
- The window drawn off the screen, light and dark: with the maintainer's own dictations, with four months of made-up use, and with nothing; in each stretch; at its narrowest; with the pointer on a square of the map and on a transcript; and whole, toolbar included, kept off every display.
- By the maintainer, for five minutes on their screen, in a test window built from the same code with their own dictations: the page, pointing at the year map, search and Copy. They liked it and found that rows jumped when Copy showed, which is fixed: drawn with and without the pointer on a row, no other row's pixels change.
- Tests for what a step of the first tile's line says, for the toolbar holding Settings alone, and for the template the panel opens on: a chip chosen and nothing written, As written beside a default, a template's shortcut, no app, an app without a bundle identifier.
- A copy of the maintainer's database, as 0.4.3 left it, opened with this version: every transcript was counted once, and both apps kept the template they were on. The copy was deleted.
- The line's note drawn at the first, middle and last steps of a week, a month and all time, and the search field drawn empty and with words.
- With the maintainer's yes, once on their screen in a test window built from the same code: the pill in both looks, listening and then holding words with Paste. Every round button's ring measured 68 by 68 pixels, and the Floating background faded out before the window's edges. The Lab was in that look too and has since been replaced.

Not yet tried:
- On the screen: the note that follows the pointer along the first tile's line, the search field where it is now, over the transcripts, and the menu of how many to keep. The line's note uses the same hover as the year map's, which the maintainer saw working.
- The panel's microphone as a round button. Its glass can't be drawn off the screen, only its shape.
- The template staying chosen, in the app itself.
- Holding keys together on a real keyboard. A single key on its own, in 0.4.2 and 0.4.3, has only been run in tests too.
- The pill and the window inside the app itself, rather than in a test window.
- The menu bar icon's new menu, and opening OmanAI again.

Known limits:
- The numbers start with the transcripts that were kept when this version first ran. What was dictated before with transcripts off, or deleted, was never counted.
- Pages, "times typing" and time saved are worked out, not measured: 275 words a page, and typing at 40 words a minute, which nobody can change yet.
- Speed is words over the whole time a dictation ran, pauses included, so it reads lower than the person speaks.
- Your English counts from this version on, so earlier weeks show nothing.
- An app's icon is found by its name. An app that was renamed, removed or lives outside the usual folders gets its first letter instead.
- The year map always shows 53 weeks, and its shades are set by the busiest day shown, so one very long day makes the others pale.
- Deleting every transcript leaves the numbers, and nothing in the window resets them.
- The chip chosen is kept for each app. An app nothing was chosen in yet starts on the default from Settings, not on the chip chosen last anywhere else.
- A template's shortcut rewrites once and leaves the chosen chip as it was. Someone who only ever uses the shortcut sees the default chip in the panel.
- The glass draws its own one-pixel dark line on each side of a round button, just outside the ring. Counting those lines, a button is 70 by 68 pixels; the ring itself is round.

## 2026-11-12 — Spending's fixes: what has been tried, and what hasn't

Tried: tests for noting each text written and marking it when it is put back, a change counting as the action it changes, a failed request noting nothing, a store that fails leaving the result alone, the bars, the actions, the apps, the earlier requests without a kind, the scales and the words of the details card. The page and the details card were drawn off the screen, light and dark, and looked at.

Not yet tried: pointing at the chart in the running app. The card follows the pointer through SwiftUI's hover, which can't be drawn off the screen.

Known limits:

- Only texts written from the release that brings this are counted, so earlier days show money but no fixes
- A text counts as put back when Replace or Insert pasted it. If the app ignored the paste, or the person pressed ⌘Z afterwards, it still counts
- Apple's on-device model costs nothing, so its texts add fixes but no money

---

## 2026-11-12 — Dictation's keys, models and buttons: what has been tried, and what hasn't

Tried: tests for Option and Command on their own (holding, tapping, one key for both, a key used in a shortcut), ✨ opening the panel with the words and Insert putting the result at the cursor, Copy last transcript, how many transcripts are kept, sounds, muting, the chosen microphone, a space after and Return. The new models were downloaded and given the sentence spoken by `say`: Parakeet TDT v2, Parakeet Redux and Whisper Small wrote it word for word, Whisper Small with "ANA" for Anna. Every Settings page was drawn off the screen and looked at.

Not yet tried:

- Option and Command on a real keyboard, and the microphone, sounds and muting on real devices. The keys are watched through macOS's event monitors, which only run in the app
- The ✨ button and Copy last transcript by hand
- The pill's look in the website's films: the filming ran while the Mac was locked and recorded the lock screen

Known limits:

- With a key on its own for Hold to dictate, a dictation starts 0.15 seconds after the key goes down. Someone who holds Option while typing an accent, as the Romanian keyboard does for ș and ț, can start one for a moment before the letter cancels it. A Command key avoids that
- Mute the Mac uses the output device's own mute. A device without one, such as some displays' speakers, stays as it is. If OmanAI quits during a dictation, the Mac stays muted
- Return is pressed 0.15 seconds after the paste. An app that pastes later than that could send before the words are in
- Canary 1B v2 was tried and left out: its first preparation for the Neural Engine ran past 15 minutes on an M1 Pro. Parakeet Redux took 26 seconds for the same step, about as long as Parakeet Unified

---

## 2026-11-12 — Dictation: what has been tried, and what hasn't

Tried: the maintainer dictated with the microphone in a signed test copy, with Parakeet Ultra. It worked, but its first words came about 10 seconds late, which led to the models that stream. Each model was then given a sentence spoken by macOS's `say`, a tenth of a second at a time as a microphone would give it. Apple's model, Parakeet Unified, Nemotron Unified, Parakeet Ultra and Whisper each wrote "Please send the report to Anna before Friday. Thank you." word for word. Parakeet Unified showed its first words 1.7 seconds after the sentence began, Nemotron 2.0 seconds and Parakeet Ultra 3.0 seconds, each growing word by word after that. Whisper wrote nothing for three seconds of silence. The pill was shown on the screen once in both looks and both places.

Not yet tried:

- The models that stream with a real microphone, and the new Settings: the list of models, the Look pictures, Words and Transcripts
- The cancel button, the moving menu bar icon and the panel's microphone buttons by hand
- The pill at the bottom of the screen since its room below was added
- The person's own words with real speech. They are checked against what a model writes, and Apple's model and Whisper are told to expect them; a word a model mishears badly is not caught
- A real speaker of another language. The downloaded models garbled a French sentence read by the Mac's French voice, which says more about that voice than about them
- Bluetooth headsets, which drop to call quality while their microphone is open

Known limits:

- Parakeet Ultra and Nemotron set to Automatic can't be told the language. Spoken in a language outside their 25, they write something wrong rather than nothing
- Whisper reads the words not yet settled again every second, so its live words trail by a second or two and a long dictation keeps the Neural Engine busy
- Nemotron takes its language when it loads, so changing the language loads it again
- The first time a downloaded model loads, Core ML prepares it for the Neural Engine: 23 seconds for Parakeet Unified. That happens at the end of its download, and later loads take about 0.2 seconds. If macOS clears OmanAI's cache, the next load prepares it again; the model is loaded a few seconds after launch for that reason, and the pill shows it loading while the microphone already listens. Each download here took about 2 to 5 minutes
- The Floating look blurs what is behind it with the same undocumented Core Animation layer as the panel's backdrop. If a macOS drops it, the words keep only the darkening and their shadow, which may be hard to read over a bright window

---

## 2026-11-12 — The marks after a proofread have only been seen over dark glass

Tests cover what is marked and how it is counted, and the marked text was drawn on its own, selectable and not, where it looks as intended. The marks were then filmed on the real panel, in the harness that makes the website's recordings. Over dark glass the tint on the new words and the red, struck-through old words read well, both at once and after a click on the count. The two pictures are in the documentation, under The result. Over light glass they have not been seen.

The whole result panel cannot be drawn off the screen. ImageRenderer leaves out what AppKit draws, which is the scrolling text and the field to make a change, and drops the glass at random. A window placed off every display draws only its AppKit parts. So seeing the panel means putting it on the screen.

---

## 2026-11-12 — The website's recordings and pictures: what 0.3.6 replaced, and what it did not

All four recordings were filmed again with 0.3.6, for the header and for Use cases, and the pictures of the General, Writing and Spending pages are new. Proofread is in the header again: it keeps the lower case, says "4 changes" and tints the words it changed. A short answer starts at the top of its box while it is written.

What is still not as it should be:

- The Proofread recording ends on its result. The filming stopped by itself at 8.2 seconds, before the count and Replace were pressed, and why is not known. It is cut at 7.7 seconds, where the pointer rests on Replace, and that picture is held. It never shows the paste
- The three new Settings pictures are each put together from two: the toolbar from the picture taken on the screen the night before, and the page under it drawn off the screen. A toolbar drawn off the screen has a box around every tab, where on the screen only the chosen one has one, so the toolbar could not be drawn that way
- The pictures of Styles, the style editor, Shortcuts and Key & Permissions, and of the panel's first screen, a rewrite's result, Explain and Compose, are from 0.3.4. Those screens have not changed since

Each recording in the header that ends with a paste carries `data-at` in `site/index.html`, the second at which it pastes, and the chat drawn under the panel changes then. A recording that is cut again needs that number measured again.

The recordings under Use cases show a whole desktop, so on a phone their text is too small to read.

The new look was checked in Chromium only, at five widths. Safari, Firefox and a real phone were not tried.

---

## 2026-11-12 — Proofread is slower than the other actions on Haiku

Proofread makes Haiku think before it writes, because without thinking it got about one proofread in four wrong. A short proofread takes about 1.7 seconds on Haiku (nine in ten under 2.7), where a rewrite takes about 0.9. It costs about $0.0002, and about $0.0004 for a message of ninety words. The quality setting does not change this. On Sonnet a proofread takes about 1.2 seconds, as before.

A long text waits longer before anything shows. An email of 290 words took about 5 seconds on Haiku and on Sonnet, three times each, and for the first 3 to 4 of them the panel only showed that it was working. Every one of its fourteen mistakes was corrected and its line breaks were kept. It cost about $0.0008 on Haiku and $0.01 on Sonnet.

The speeds on the website and in the README are from the run of eleven tasks made with 0.3.4. Each now carries a sentence about Proofread. The table itself has not been measured again.

---

## 2026-11-12 — What the checks on real answers do and don't show

The numbers in DECISIONS.md come from checks on the text of each answer: a word is there or not, the line breaks are kept, the answer is not longer than its text. They catch a wrong letter case, a missing apostrophe, a second version or a comment on the first, an added greeting, the wrong language. They do not judge whether a rewrite sounds like the person, or whether an explanation is a good reading.

There are 29 kinds of text, almost all English and short. Seventeen were looked at while the wording was tuned, so the ten that were not are the fairer measure: 1 answer in 80 failed there. Two more send a picture of a made-up conversation, drawn by the test, the way the Screen switch sends a screenshot: all 12 answers used it. A capture of a real window was not tried.

What still goes wrong, about once in a hundred answers: "its" left where "it's" is meant, and an explanation of a grudging message that gives its warning inside the first paragraph instead of a second one.

A proofread that failed under the first new wordings is worth knowing about, though it no longer happens: the model wrote the text out with mistakes still in it, then "Wait, I need to correct that" and a second version. Should an answer like that ever come back, it is all in the panel before anything is pasted. Nothing in the app catches it.

Every run that asks the models costs money: the runs of this night cost about $2.50 in all.

---

## 2026-11-12 — The count of writing habits is simple on purpose

`WritingHabits` counts sentence starts and, in English text, the word "i". A tie counts as formal writing, so a two-sentence text with one capital start gets its capitals corrected. A sentence that starts after "e.g." or "etc." is counted like any other. Text in a script without capital letters says nothing, and the text being proofread then decides.

Whether a message ends without a full stop is taken from one-line samples only, because an email ends with a name.

Apostrophes left out are recognised from a list of English contractions. In another language a template that leaves apostrophes out is not noticed, and Proofread adds them.

Proofread with As written always adds missing apostrophes, even for someone who leaves them out on purpose. A template whose samples leave them out keeps them out.

---

## 2026-11-12 — The website's nginx image has to be moved on by hand

`site/Dockerfile` names one exact image. Nothing reminds anyone when nginx publishes a newer one. To move it on: `docker buildx imagetools inspect nginx:stable-alpine`, put the version and digest in the Dockerfile, build and try it locally, push.

Cloudflare on this domain keeps a copy of a file only when its address has no question mark in it. So `styles.css?v=3` and `app.js?v=3` always come from the server itself, which is what a redesign needs, and a recording or picture that changes must change its file name, not get a number after a question mark.

Cloudflare adds its Web Analytics script to pages on this domain. The site's response headers stop it from loading, which shows as one blocked-script line in the browser's console. Turning it off for this hostname is a Cloudflare setting and was left to the maintainer.

---

## 2026-11-11 — Apple's on-device model: what it does well and badly

Run through the app's own client on a Mac with macOS 27. It is available and runs locally. The first request after a pause takes 5 to 9 seconds; after that the first word comes in 0.6 to 1 second and the whole answer in 1 to 2.5.

Plain proofreading in English is good. Beyond that it is weak: asked to rewrite a formal note in a casual style it returned the note almost unchanged, "make it polite but still firm" only swapped words, a reply was signed with the other person's name, "Fine. Do whatever you think is best, I guess." was read as casual permission, and Romanian came back wrong once and as a guardrail error once.

Claude was then run through the API on the same eleven tasks and on many more. See the entries of 2026-11-12 below.

---

## 2026-11-11 — Settings has only been tried on macOS 27

The window follows the height of each page, which a grouped form reports when it is told to take its own size. That is seen working on macOS 27 only. Should macOS 14 or 15 report next to nothing, the page scrolls at full height instead (`SettingsForm`), and that path is untried too.

The alert that asks before a style is deleted has not been tried by hand. SwiftUI's own confirmation did not appear after a click made inside the test process, so the sheet uses `NSAlert`, which was not opened in a test: it would have needed a click on the maintainer's screen.

---

## 2026-11-11 — Spending reads every stored request

All time needs every request ever recorded, so the page reads them all each time Settings opens. That is fine for tens of thousands of rows. If it ever gets slow, the sums can be made by SQLite instead.

Timed on 2026-11-12 in a debug build: summing up 1,000 requests takes 6 ms, 10,000 takes 47 ms, 50,000 takes 0.23 s and 200,000 takes 0.9 s, on the main thread when the page opens. At a hundred requests a day that is years away from being felt.

---

## 2026-11-11 — Trying Settings without showing a window

- A window with a title bar placed outside every display is pulled back onto one when it is shown. Replacing `constrainFrameRect(_:to:)` for the test process keeps it where it is put
- `screencapture -l` writes nothing for a window that is on no display. The window's frame view can draw itself with `cacheDisplay(in:to:)` instead. Drawn that way the toolbar gets a border round every tab, which the real window doesn't have
- Never close a SwiftUI sheet from outside. `endSheet` left SwiftUI's own state set, the sheet came straight back, and a loop that waited for it to go ran for about twenty minutes on the maintainer's screen, until they pressed Done
- `Charts` centres an axis label between marks, or starts it at its mark. With a label for only some bars, neither is under the bar it names. `AxisMarks(preset: .aligned)` on the middle of each bar is. An `anchor` on the label changed nothing
- The Spending chart alone can be drawn to a picture with `ImageRenderer`, with no window at all. That is how its labels were checked for every length of month

---

## 2026-11-11 — The backdrop depends on Core Animation classes outside the public headers

The slight blur behind the panel is a `CABackdropLayer` with a `CAFilter` of type `variableBlur`, neither of which Apple documents. `BackdropBlur` looks them up at run time. If a future macOS removes them, `PanelBackdrop.isAvailable` turns false and the panel shows frosted glass with no backdrop, as 0.3.2 did. If only `variableBlur` goes, it falls back to one even blur shown through a fading mask, which also has no line but blurs less just outside the tiles. If they stay but behave differently, the backdrop could look wrong: measure it again with the checkerboard method under Tooling gotchas.

The filter's numbers were found on macOS 27 on a display with two pixels per point: a radius of 1.5 blurs by 3 points. Not checked: a display with one pixel per point, and macOS 26.

---

## 2026-11-11 — The panel's steady look relies on an AppKit method outside the public headers

macOS draws glass darker and flat in a window that isn't key, and a tinted button turns gray. A pinned panel is rarely key, so `FloatingPanel` answers `hasKeyAppearance` with yes and its glass stays as it is when focused. AppKit declares that method only privately. If a future macOS stops asking it, the panel goes back to dimming when it loses focus and nothing else breaks. To check, show the panel, make another window key and compare captures: the glass should not change.

Not checked: what else in the panel reads the same answer, such as the colour of selected text in a pinned panel that isn't focused.

---

## 2026-11-11 — Back sometimes did nothing, and the panel can feel slow

Up to 0.3.0, Apple's Writing Tools ran inside OmanAI's panel. After text in the panel was clicked or selected, macOS set up its floating Writing Tools button and a host window over the panel, which could sit on Back and take the click. The system log shows this as `CampoLightweightUI` events in OmanAI's process. Writing Tools is now off for OmanAI's own text, but Back has not been re-checked on screen. If it misses again, `/usr/bin/log show --last 1h --predicate 'subsystem == "com.romanbitca.oman"'` shows whether the press arrived.

The lag had two causes, both in the panel since before 0.3.0 and both fixed after 0.3.2. While Claude was writing, the glow around the tile was drawn again for every frame and kept the main thread 99% busy. And every screen change ran at about 34 frames a second on a 120 Hz display, because the tiles sat in Apple's glass container. macOS recorded no hang because the app never stopped answering. To measure again, count how many of the display's refreshes the main thread answers on time while a screen changes; `sample` on the running app shows where the time goes, though attaching it adds stalls of its own.

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

The main thread spun at 100% in `NSAutoFillHeuristicController`, walking SwiftUI's key views (`FocusNavigationSequence.next`), and buttons then looked broken. Worked around in `OmanMain.swift` with the `NSAutoFillHeuristicsEnabled` default.

Since 2026-11-11 it can be reproduced on demand, in a window that hosts the panel without that default: click the instruction field on the home screen, then press Compose. The main thread never comes back. With the default set, the same clicks run through with no stall, which is the first check that the workaround holds. Anything that hosts the panel outside the app, such as a preview, must set the default too. If the app freezes anyway, run `sample $(pgrep -x OmanAI) 2` to see where it is stuck.

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
- On GitHub's runner `swift test` runs every test target in one process, much slower than on this Mac, and the main actor can be busy for seconds at the start. A test that waits for something must allow for that: `eventually` in the UI tests waits up to 10 seconds. At 2 seconds, eleven dictation tests failed there on 2026-11-12 and none here.
- A SwiftUI shape drawn above a `WindowDragArea` takes the click and does nothing with it, so mark it `.allowsHitTesting(false)`.
- Fully clear pixels in the panel pass clicks to the app behind. Liquid Glass in a custom `Shape` counts as clear, unlike glass in a capsule or rounded rectangle, and so did a dark bar drawn on it. A 2% white fill in the same shape, behind the drag area, makes it clickable. Unit tests can't see this: check with real mouse events.
- `log` is a zsh builtin, so reading the system log needs `/usr/bin/log`.
- Glass can be checked on screen, with the maintainer's OK: host the panel in a borderless panel under the menu bar, make it the key window, let it draw for about a second, and capture that area with `screencapture -R`. Glass in a window that isn't key is drawn flat and gray, which made several captures misleading. Control Center opens through Accessibility by pressing the "Control Center" item that `MenuBarAgent` owns in the menu bar (System Events can't see it); wait about three seconds before capturing it.
- To compare with Control Center by numbers, put a window with a black and white checkerboard of 32-point squares behind both, at level `.floating`. Per square, read the white level, the black level, and the width of the edge to the next square: the 10% to 90% width divided by 2.563 is the blur's sigma. The backdrop's numbers were found this way.
- The window server's blur (`CGSSetWindowBackgroundBlurRadius`) only shows where the window's own pixels have an alpha of at least 2/255. It is all or nothing there, so a soft edge needs stacked windows, and every step between them shows as a line on text. The app used it until `CABackdropLayer` replaced it.
- To compare a tile's colour with Control Center, put a plain colour behind both and read the colour through a tile and in the gap beside it. The gap gives what the tile sees. Control Center's tile turns 0/0/0 into 13/13/13, 45/45/45 into 43/43/43, 90/90/90 into 73/73/73, 81/27/18 into 89/24/11, 85/54/18 into 84/46/0, 18/36/81 into 15/37/91 and 18/63/27 into 0/60/15 (percent, macOS 27).
- Inside a `GlassEffectContainer` the container draws the glass for every view in it. A filter such as `.saturation` on one of those views changes its content and not its glass, so it has to go on the container. A blend mode on a layer drawn over the glass does work on a single view.
- A filter on the content of a glass view cuts that content off from the glass. With `.saturation` on a tile's content, a text field's placeholder turned from light to dark gray.
- Glass in a window that isn't key can't be kept active from SwiftUI: setting `appearsActive` or `controlActiveState` in the environment changes nothing. It follows the window's `hasKeyAppearance`.
- A `GlassEffectContainer` makes every animated frame expensive: the panel's screen changes ran at 34 frames a second inside one and at 119 without, measured in an optimised build. Its spacing and glass identities made no difference.
- Glass is drawn again for every size it takes, so a `scaleEffect` on glass runs at about half the display's rate. Moving glass with `offset` or matched geometry is cheap.
- A SwiftUI animation that draws, such as an `AngularGradient` whose angle changes in a `TimelineView`, is rasterized on the main thread for every frame. A `CAGradientLayer` with a `CABasicAnimation` costs the app nothing while it runs.
- To measure smoothness, add a display link to the hosting view and count the gaps between its callbacks: a gap of two refreshes is a frame the main thread missed. Read the main thread's own processor time alongside it. Use an optimised build (`swift test -c release -Xswiftc -enable-testing`), and don't force `CATransaction.flush()` in the loop, which makes SwiftUI draw more often than the display refreshes.
- A test that shows the panel and waits in a loop holds the main actor, so the panel's own tasks, such as an answer arriving, never run. Call `await Task.yield()` in the loop.
- Clicks can be tested without moving the pointer: make `NSEvent.mouseEvent` values for the panel's window and hand them to `NSApp.postEvent`.
- `NSVisualEffectView.maskImage` ignores an image with only an alpha channel. Give it black pixels with the fade in their alpha.
- `gh` on this Mac has more than one account, and the active one may be a work account that can only read this repository. Then pushes and `gh variable get` fail with 403. Run them with the maintainer's account for that command only, `GH_TOKEN="$(gh auth token --user romanbitca)"`, rather than switching the active account.
- Don't check permissions by reading the panel's text through System Events: most of it isn't exposed. Read the `AUTHREQ_RESULT` lines in the `tccd` log instead.
- Liquid Glass can't be checked offscreen: `cacheDisplay` draws no glass, and any tinted glass blanks the whole bitmap. Real rendering needs a person looking at it, or Screen Recording permission.
- A backdrop made from `NSVisualEffectView` or from glass always shows a tint: a gray veil or card over a white app, a light one over a dark app. The maintainer rejected three such versions. A `CABackdropLayer` with only a blur filter on it has no tint, and fading its window fades the blur.
- A stroked `Capsule()` can draw a short stray line at each end: its corners are continuous by default, and they don't fit a shape that is all corner. `Capsule(style: .circular)` strokes cleanly. Filling is fine either way.
- A window's first text field takes the keyboard when the window is first shown, and SwiftUI then draws its focus. `makeFirstResponder(nil)` after showing gives the keyboard back to the window.
- `ImageRenderer` can't draw a `TextField` and shows a yellow box with a no-entry sign in its place. `cacheDisplay` on a hosting view draws it.
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

