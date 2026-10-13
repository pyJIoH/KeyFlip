# Testing KeyFlip

## Automated coverage

Run `bash scripts/test.sh` from the repository root. The standalone runner currently contains **45 scenarios** and exits with status 1 if any assertion fails.

| Area | Covered cases |
| --- | --- |
| Modifier taps | Both Option keys; left Control; ignored right Control/Command; chords; both sides held; typing/mouse cancellation; long holds; exact timeout boundary; backwards timestamps; unmatched/wrong release; duplicate press; reset and recovery; repeated gestures |
| Word lookup | English/Russian; punctuation; trailing spaces and their limit; tabs/newlines/CRLF/Unicode whitespace; empty input; UTF-16 emoji/combining sequences; length boundary; clipped context; document offsets and overflow |
| Transformations | Complete English/Russian alphabets and ё; mixed case; Unicode expansions; symbols/emoji/whitespace; multiline and empty input; alphabet detection; unmapped characters |
| Focus resolution | Independent providers; nested editors; provider priority; cycles/self-cycles; unreadable candidates; empty candidates; traversal depth limits |

Run `bash scripts/build-app.sh` followed by `bash scripts/check-platform.sh` in a logged-in macOS desktop session. These checks cover:

- Command+V down/up events, virtual keycode, generic and device-specific Command flags, loop-prevention tags, and AppKit's modifier interpretation. **No events are posted.**
- Clipboard staging/restoration, multiple items, binary and Unicode representations, newer-copy protection, empty clipboard, repeated restoration, and automatic restoration on release. A **private, uniquely named pasteboard** is used.

Add `--with-layouts` to check installed U.S./ABC ↔ Russian conversion, both directions, mixed case, multiline text, emoji preservation, and rejection of mixed Latin/Cyrillic input. Enable the layouts in macOS first. This check reads the selected layouts without switching the active input source.

GitHub Actions runs the core suite and signed release build. Desktop-dependent checks are explicit local commands because hosted runners do not represent a user's permissions, input sources, or editors.

## What automated tests do not establish

There is no claim of complete line coverage or universal application compatibility. The suite does not automate macOS permission dialogs, login-item registration, real modifier delivery, editor-specific Accessibility timing, Secure Input activation, or paste/Undo behavior in third-party applications. These require the manual checks below.

## Manual regression checklist

Use disposable text in an empty draft or document. Do not send the draft. Repeat the main conversion cases in a native editor such as TextEdit, a browser input/textarea/contenteditable, and each supported Electron composer, including Codex and Claude Desktop.

The local [editor fixture](../Tests/Fixtures/editor.html) provides three disposable browser fields and an input-event counter. Open it in a browser through Finder. It has no network calls or submit action.

| Check | Expected result |
| --- | --- |
| Type `ghbdtn`, tap either Option alone | `привет`; Russian source active |
| Tap Option again | `ghbdtn`; English source active |
| Tap left Control twice | `GHBDTN`, then `ghbdtn` |
| Select `Ghbdtn` inside a longer sentence, then Option | Only selection becomes `Привет`; replacement stays selected |
| Select `Hello МИР` and tap left Control | `hELLO мир`; surrounding text unchanged |
| Put caret after `first ghbdtn `, then Option | `first привет `; trailing space and caret position retained |
| Convert a word after an emoji; invert selected `straße` | Correct UTF-16 offsets; expanded `STRASSE` remains correctly selected |
| Select multiple lines and convert/invert | Line breaks and surrounding content retained |
| Press Option+Arrow, Control+A, Command+C/V, right Control, or hold Option > 1 second | No extra conversion on modifier release |
| Undo after a conversion | Host editor restores its prior text |
| Copy text or rich content before converting | Clipboard restored after conversion |
| Make a new copy during a pending conversion | Newer clipboard content is not overwritten |
| Type/click/switch apps during pending work | Pending replacement stops; no text is inserted into a different editor |
| Try a password field or enable Secure Input | No text conversion; excluded/paused state reported |
| Restart an Electron app and immediately try its main composer | Editor support initializes or an explicit failure is shown; no duplicate paste |
| Pause and resume; revoke and restore permissions | Monitoring stops and resumes with accurate status |
| Enable Launch at login, then sign out/in | One installed copy starts from the intended path |

If a paste cannot be confirmed, inspect the text before retrying. KeyFlip deliberately avoids a second automatic paste.

## Recording a compatibility issue

Include the KeyFlip version, macOS version, application/version, field type, selected-text versus last-word mode, and the status message from KeyFlip Settings. Use a small invented input and its expected/actual output; do not include private draft text or clipboard contents.
