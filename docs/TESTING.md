# Testing KeyFlip

## Automated coverage

Run `bash scripts/test.sh` from the repository root. The standalone runner currently contains **53 scenarios** and exits with status 1 if any assertion fails.

| Area | Covered cases |
| --- | --- |
| Modifier taps | Both Option keys; left Control; ignored right Control/Command; chords; both sides held; typing/mouse cancellation; long holds; exact timeout boundary; backwards timestamps; unmatched/wrong release; duplicate press; reset and recovery; repeated gestures |
| Word lookup | English/Russian; punctuation; trailing spaces and their limit; tabs/newlines/CRLF/Unicode whitespace; empty input; UTF-16 emoji/combining sequences; length boundary; clipped context; document offsets and overflow |
| Transformations | Complete English/Russian alphabets and ё; mixed case; Unicode expansions; symbols/emoji/whitespace; multiline and empty input; alphabet detection; unmapped characters |
| Focus resolution | Independent providers; nested editors; provider priority; cycles/self-cycles; unreadable candidates; empty candidates; traversal depth limits |
| Typed word | Trailing spaces and their limit; Backspace; leading/other whitespace; multi-character input; length overflow until the next word; retyped keys; matching editor text at a word boundary, no-break spaces, surrogates; copied-line detection |

Run `bash scripts/build-app.sh` followed by `bash scripts/check-platform.sh` in a logged-in macOS desktop session. These checks cover:

- Command-V and Command-C down/up events, virtual keycode, generic and device-specific Command flags, Backspace and Unicode typing events without modifiers, loop-prevention tags, and AppKit's modifier interpretation. **No events are posted.**
- Clipboard staging/restoration, multiple items, binary and Unicode representations, newer-copy protection, empty clipboard, repeated restoration, saving before a copy and staging after it, and automatic restoration on release. A **private, uniquely named pasteboard** is used.

Add `--with-layouts` to check typed characters with Shift and Caps Lock, installed U.S./ABC ↔ Russian conversion, both directions, mixed case, multiline text, emoji preservation, and rejection of mixed Latin/Cyrillic input. Enable the layouts in macOS first. This check reads the selected layouts without switching the active input source.

GitHub Actions runs the core suite and signed release build. Desktop-dependent checks are explicit local commands because hosted runners do not represent a user's permissions, input sources, or editors.

## What automated tests do not establish

There is no claim of complete line coverage or universal application compatibility. The suite does not automate macOS permission dialogs, login-item registration, real modifier delivery, editor-specific Accessibility timing, Secure Input activation, or paste/Undo behavior in third-party applications. These require the manual checks below.

## Manual regression checklist

Use disposable text in an empty draft or document. Do not send the draft. Repeat the main conversion cases in a native editor such as TextEdit, a browser input/textarea/contenteditable, each supported Electron composer, including Codex and Claude Desktop, and editors without Accessibility text such as Terminal, iTerm2, and a JetBrains IDE.

The local [editor fixture](../Tests/Fixtures/editor.html) provides three disposable browser fields and an input-event counter. Open it in a browser through Finder. It has no network calls or submit action.

| Check | Expected result |
| --- | --- |
| Type `ghbdtn`, tap either Option alone | `привет`; Russian source active |
| Tap Option again | `ghbdtn`; English source active |
| Tap left Control twice | `GHBDTN`, then `ghbdtn` |
| Select `Ghbdtn` inside a longer sentence, then Option | Only selection becomes `Привет`; caret after it, nothing selected |
| Select `Hello МИР` and tap left Control | `hELLO мир`; surrounding text unchanged |
| Put caret after `first ghbdtn `, then Option | `first привет `; trailing space and caret position retained |
| In Terminal or a JetBrains editor, type `ghbdtn`, tap Option, tap again | `привет`, then `ghbdtn`; source switches each time |
| Type `ghbdtn`, Backspace twice, type `tn`, tap Option | `привет` |
| Type `ghbdtn`, click elsewhere and back, tap Option | In an Accessibility editor, `привет`; otherwise only the source switches |
| In a browser address bar, type a word with inline completion, tap Option | Typed word converted; the completion is removed |
| Select text in a JetBrains editor, tap Option; tap Option with no selection | Selection converted; with no selection, the line is not duplicated |
| Convert a word after an emoji; invert selected `straße` | Correct UTF-16 offsets; caret directly after the expanded `STRASSE` |
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
