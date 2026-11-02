# Changelog

Notable user-visible changes to KeyFlip. Versions match `CFBundleShortVersionString` in `Resources/Info.plist`.

## [Unreleased]

## [0.4.0] - 2026-11-01

### Added

- Conversion in editors that do not expose their text through macOS Accessibility, such as terminals and many IDE, Electron, and web editors. A word typed just now is erased with Backspace and retyped in the other layout. When the editor does expose its text, KeyFlip first checks that the text before the cursor is exactly that word.
- Inline completions, such as in a browser address bar, are removed before the typed word is retyped.
- Selections the editor does not expose are copied with Command-C, converted, and pasted back with Command-V, then the clipboard is restored. Terminals are excluded. A single copied line ending in a line break is rejected, because code editors copy the current line when nothing is selected.
- Platform checks for Command-C, Backspace, and Unicode typing events, for saving the clipboard before a copy, and for typed characters with Shift and Caps Lock.

### Changed

- A converted selection is no longer reselected; the cursor is placed after the replacement.
- If KeyFlip cannot read an editor's target text, it now switches the input source and reports that no text was changed, instead of only showing an error.
- Virtual machines and remote desktops only get the Mac input source switch.

### Privacy

- To retype a word, KeyFlip now keeps the current word (at most 256 characters) and the spaces after it in memory. It is cleared by clicks, navigation keys, shortcuts, Return, Tab, and application switches. Typed text is never written to disk or sent over the network.

## [0.3.7] - 2026-10-12

Initial open-source release.

- Tap Option to convert text between the English and Russian layouts and switch the input source; tap left Control to invert letter case.
- Selected text takes priority; otherwise KeyFlip changes the word before the cursor.
- Replacement through macOS Accessibility and a normal paste, with verification and clipboard preservation.
- Electron editor support, Secure Input and password-field exclusion, launch at login, and diagnostic commands.

[Unreleased]: https://github.com/pyJIoH/KeyFlip/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/pyJIoH/KeyFlip/compare/v0.3.7...v0.4.0
[0.3.7]: https://github.com/pyJIoH/KeyFlip/releases/tag/v0.3.7
