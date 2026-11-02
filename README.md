# KeyFlip

A small, offline macOS menu bar app for correcting text typed with the wrong English/Russian keyboard layout and inverting letter case. Written in Swift, with no third-party dependencies.

[MIT license](LICENSE) · [Contributing](CONTRIBUTING.md) · [Testing guide](docs/TESTING.md) · [Changelog](CHANGELOG.md)

| Tap a key by itself | Action | Example |
| --- | --- | --- |
| Left or right **Option** | Convert English ↔ Russian and switch the active input source | `ghbdtn` ↔ `привет` |
| **Left Control** | Invert each letter's case | `Hello ПРИВЕТ` ↔ `hELLO привет` |

Selected text takes priority. With no selection, KeyFlip changes the word immediately before the cursor. For a word you have just typed, this also works in terminals and other editors that hide their text from macOS Accessibility (see [How text is replaced](#how-text-is-replaced)). Release the key within one second; typing, clicking, scrolling, or pressing another modifier cancels the gesture. Right Control and Command do not trigger conversion. Normal keyboard shortcuts keep working.

## Requirements

- macOS 13 or later.
- Swift 5.9 or later, supplied by Xcode or Apple's Command Line Tools, to build from source.
- U.S. or ABC and a Russian keyboard layout enabled in macOS Keyboard settings.
- Accessibility and Input Monitoring access for the installed app.

The build script produces an app for the current machine's architecture. There are no external packages, API keys, accounts, or network services to configure.

## Build and install

From the repository root:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
```

The app is written to `dist/KeyFlip.app`, with the license included in its Resources directory. The script signs it locally and verifies the signature. Build caches and generated bundles are ignored by Git.

1. Quit any running copy of KeyFlip.
2. Move `dist/KeyFlip.app` to `~/Applications` or `/Applications` using Finder. Keep one installed copy at a stable path.
3. Open that copy in Finder. Settings are also available from its menu bar icon.
4. Grant **Accessibility** and **Input Monitoring** access using the buttons in Settings. The Accessibility permission may appear under **Device Control and Data Access** on some macOS versions. If the app is absent from a permission list, add the installed `KeyFlip.app` with the **+** button.
5. Quit and reopen the app if macOS requests it. Both permission indicators should show **Allowed**, and the status should show **ACTIVE**.
6. Choose the enabled English and Russian layouts. Enable **Launch at login** if desired.

### Signing and updates

By default, `build-app.sh` uses an ad-hoc signature. Rebuilding changes the app's identity and can invalidate its macOS permission grants. If a new build remains paused despite enabled switches, remove the old KeyFlip entries from the two permission lists, add the installed copy again, and relaunch it.

To use an existing code-signing identity from your keychain:

```sh
KEYFLIP_SIGN_IDENTITY='Your signing identity' bash scripts/build-app.sh
```

This repository's build script does not notarize or package the app for public distribution. Moving an installed app may also require disabling and re-enabling **Launch at login** from its new location.

## Usage and behavior

Type `ghbdtn`, release the keys, and tap Option: the word becomes `привет` and the Russian input source becomes active. Tap left Control to get `ПРИВЕТ`. You can also select an existing word, sentence, or multiple lines before invoking either action. The converted text replaces the selection and the cursor is placed after it; the text is not left selected.

- “Last word” means the whitespace-delimited text before the caret, including attached punctuation. KeyFlip can reach back across up to eight trailing spaces, but never across a trailing tab or newline.
- Automatic word conversion is limited to 256 UTF-16 units. Explicit selections can contain up to 100,000 UTF-16 units.
- Layout conversion follows physical key positions in the selected installed layouts; it is not transliteration or translation.
- Selections containing both Latin and Cyrillic letters are rejected for layout conversion. Case inversion still works on mixed-language text.
- Digits and punctuation follow the current input source when no Latin or Cyrillic letters indicate a direction. Unmapped characters, including emoji, are preserved.
- In an empty field, Option switches the input source without changing text. If KeyFlip cannot find text to change, it switches the source and reports that no text was changed.
- Case inversion uses Unicode casing. Some characters can expand, such as `ß` → `SS`, so inversion is not reversible for every language.

## How text is replaced

KeyFlip tries these strategies in order:

1. **A word you just typed.** KeyFlip remembers the characters typed since the last click, arrow key, Return, Tab, shortcut, or application switch. It erases the word with Backspace and types the converted word. This needs no Accessibility support and no clipboard, so it also works in editors that hide their text, such as terminals and many IDE, Electron, and web editors. When the editor does expose its text, KeyFlip first checks that the text before the cursor is exactly that word; otherwise it uses the next strategy.
2. **Accessibility.** For a selection, or a word you did not just type (for example, after clicking at the end of it), KeyFlip reads the text through macOS Accessibility, selects it, and pastes the replacement. It verifies the result and leaves the cursor after the replacement; a converted selection is not reselected.
3. **Copy and paste.** If the editor does not expose its selection, KeyFlip copies it with Command-C, converts it, and pastes it with Command-V. If nothing is copied, no text is changed. Terminals are excluded, because selected terminal text is usually output. A single copied line ending in a line break is rejected, because code editors copy the current line when nothing is selected.

Virtual machines and remote desktops send keys to another system with its own input source, so KeyFlip only switches the Mac's input source there. Compatibility with every application cannot be guaranteed.

## Privacy

Password fields and Secure Input are excluded. While Secure Input is active, macOS does not deliver keystrokes to KeyFlip. To retype a word, KeyFlip keeps only the current word (at most 256 characters) and the spaces after it in memory. It is cleared by clicks, navigation keys, shortcuts, Return, Tab, and application switches, and replaced when the next word starts. KeyFlip does not write typed text to disk, keep typed-text history, or send data over the network. It reads editor text only when an action is requested.

Strategies 2 and 3 temporarily use the system clipboard, then restore all eagerly readable representations. If another copy occurs during replacement, that newer clipboard content is preserved. Clipboard managers may observe the temporary text. If the existing clipboard cannot be preserved, KeyFlip stops before insertion.

## Architecture

The pure logic lives in `KeyFlipCore`; the macOS executable owns platform integration and the UI.

| Component | Responsibility |
| --- | --- |
| `KeyFlipCore/TapDetector.swift` | Modifier press/release state machine; cancellation and timing |
| `KeyFlipCore/WordAtCaret.swift` | Bounded word lookup with UTF-16 ranges |
| `KeyFlipCore/TypedWordBuffer.swift` | In-memory current word for retyping; matching against editor text; copied-line detection |
| `KeyFlipCore/Transforms.swift` | Unicode case inversion, alphabet detection, character mapping |
| `KeyFlipCore/FocusedEditorResolver.swift` | Focus-provider traversal with cycle and depth limits |
| `KeyFlip/EventMonitor.swift` | Listen-only event tap; filters tagged synthetic events |
| `KeyFlip/Layouts.swift` | Installed input sources, physical key mappings, typed characters, source switching |
| `KeyFlip/TextAccess.swift` | Accessibility reads, editor preparation, clipboard preservation, verified, retyped, and copied replacement |
| `KeyFlip/KeyEvents.swift` | Tagged Command-C/V, Backspace, and Unicode typing events; application categories |
| `KeyFlip/AppModel.swift` | Coordinates actions, permissions, activity cancellation, login registration |
| `KeyFlip/SettingsView.swift` and `main.swift` | SwiftUI settings, AppKit menu bar/lifecycle, diagnostic entry points |

A conversion first checks for a word typed just now and retypes it. Otherwise it resolves the focused editor, reads the selection or preceding word, computes the replacement, confirms the target and selection, then sends a normal paste. It verifies the resulting text, places the caret after it, and restores the clipboard. Input or focus changes invalidate pending work. The app never retries an unconfirmed paste automatically.

Electron applications may initially expose only a shell. KeyFlip requests their accessibility support, checks application/system/window focus providers, and briefly retries while the editor becomes available.

## Tests

```sh
# Deterministic core regression tests; no desktop access or permissions needed.
bash scripts/test.sh

# Build and check synthetic key events and a private test clipboard.
bash scripts/build-app.sh
bash scripts/check-platform.sh

# Also check conversion against enabled U.S./ABC and Russian layouts.
bash scripts/check-platform.sh --with-layouts
```

The test target is a standalone executable, so use `scripts/test.sh`, not `swift test`. It works without XCTest or a full Xcode installation and returns a nonzero exit status on failure.

Platform checks need a logged-in macOS desktop session. They never send keyboard events, switch the active input source, or use the general clipboard. They do not replace end-to-end tests in real editors.

GitHub Actions runs the core tests and builds/verifies the signed app on a macOS runner. Permission flows and application compatibility remain manual checks. See [the testing guide](docs/TESTING.md) for coverage and the release checklist.

## Troubleshooting

- **PAUSED / no hotkeys:** check both permission indicators, Secure Input, and the Pause/Resume setting. Reopen KeyFlip after changing permissions.
- **Word is selected but unchanged:** read the status message in KeyFlip Settings. The host may not have accepted the paste, or the target may have changed. Check the text before retrying.
- **A word typed earlier is not converted in an app without Accessibility support:** KeyFlip can only retype words it saw you type. Select the word and tap the key again, or retype it.
- **An Electron editor is temporarily unavailable:** focus its input field and give its accessibility support time to initialize. Try a small explicit selection.
- **Wrong layout or missing layout:** enable U.S./ABC and Russian in macOS, click **Refresh**, and select the intended variant, such as Russian – PC.
- **Rebuild lost permissions:** renew grants for the installed copy as described under Signing and updates. Avoid running multiple builds with the same bundle identifier.

The visible **Test conversion** controls exercise replacement in the chosen editor. They help separate a hotkey-detection issue from a text-access/paste issue.

For permission and input-source metadata only:

```sh
dist/KeyFlip.app/Contents/MacOS/KeyFlip --diagnose
```

This command prints no editor text. Permission results from a terminal-launched process can differ from the Finder-launched app; the installed app's indicators are the primary reference.

## License

KeyFlip's source code and documentation are available under the [MIT license](LICENSE).

The project has no third-party package dependencies or bundled third-party
fonts, images, or libraries. It uses frameworks and SF Symbols supplied by
macOS; those system resources are not redistributed in this repository.
