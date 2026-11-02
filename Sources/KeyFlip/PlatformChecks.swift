import AppKit
import Carbon
import IOKit.hidsystem

/// Construct and inspect events only; never post keys or inspect another app.
func checkPasteShortcut() throws {
    let expectedFlags = CGEventFlags.maskCommand.rawValue | UInt64(NX_DEVICELCMDKEYMASK)
    for (name, key, events) in [("Paste", kVK_ANSI_V, try KeyEvents.paste()), ("Copy", kVK_ANSI_C, try KeyEvents.copy())] {
        guard events.count == 2, events[0].type == .keyDown, events[1].type == .keyUp else {
            throw AppFailure.message("\(name) must contain exactly one key down and key up.")
        }
        for event in events {
            guard event.getIntegerValueField(.keyboardEventKeycode) == key,
                  event.flags.rawValue == expectedFlags,
                  event.getIntegerValueField(.eventSourceUserData) == injectedEventTag,
                  NSEvent(cgEvent: event)?.modifierFlags.contains(.command) == true else {
                throw AppFailure.message("\(name) event lost its key, Command flags, or loop-prevention tag.")
            }
        }
    }
    func characters(_ event: CGEvent) -> String {
        var length = 0
        var units = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        return String(utf16CodeUnits: units, count: length)
    }
    let deletions = try KeyEvents.backspaces(2)
    let typing = try KeyEvents.typing("пР ", keys: [5, 15, 49]) + KeyEvents.typing("x", keys: [])
    let expected: [(Int64, String)] = [(5, "п"), (15, "Р"), (49, " "), (0, "x")]
    guard deletions.count == 4, typing.count == 8, try KeyEvents.backspaces(0).isEmpty else {
        throw AppFailure.message("Typing must contain one key down and key up per character.")
    }
    for (index, event) in (deletions + typing).enumerated() {
        let isDeletion = index < deletions.count
        let (key, text) = isDeletion ? (Int64(kVK_Delete), "") : expected[(index - deletions.count) / 2]
        guard event.type == (index % 2 == 0 ? .keyDown : .keyUp),
              event.getIntegerValueField(.keyboardEventKeycode) == key,
              event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
              event.getIntegerValueField(.eventSourceUserData) == injectedEventTag,
              isDeletion || characters(event) == text else {
            throw AppFailure.message("Typing event lost its key, character, modifiers, or loop-prevention tag.")
        }
    }
    print("Synthetic event checks passed: Command-V/C down/up, Command + left-device flag, Backspace and Unicode typing, no modifiers, event tags, AppKit modifier interpretation. No events posted.")
}

func checkClipboardIsolation() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let original = NSPasteboardItem()
    original.setString("original привет", forType: .string)
    let customType = NSPasteboard.PasteboardType("local.keyflip.test-data")
    let bytes = Data([0, 1, 2, 255])
    original.setData(bytes, forType: customType)
    let second = NSPasteboardItem()
    second.setString("second item", forType: .string)
    guard pasteboard.writeObjects([original, second]) else { throw AppFailure.message("Test clipboard unavailable.") }
    let lease = try ClipboardLease(text: "temporary", pasteboard: pasteboard)
    guard pasteboard.string(forType: .string) == "temporary" else { throw AppFailure.message("Clipboard staging failed.") }
    lease.restore()
    guard pasteboard.pasteboardItems?.count == 2,
          pasteboard.pasteboardItems?.first?.string(forType: .string) == "original привет",
          pasteboard.pasteboardItems?.first?.data(forType: customType) == bytes,
          pasteboard.pasteboardItems?.last?.string(forType: .string) == "second item" else {
        throw AppFailure.message("Clipboard representations were not restored.")
    }
    let restoredChangeCount = pasteboard.changeCount
    lease.restore()
    guard pasteboard.changeCount == restoredChangeCount else {
        throw AppFailure.message("Restoring a clipboard lease twice changed the clipboard.")
    }
    let interrupted = try ClipboardLease(text: "temporary again", pasteboard: pasteboard)
    pasteboard.clearContents()
    pasteboard.setString("new user copy", forType: .string)
    interrupted.restore()
    guard pasteboard.string(forType: .string) == "new user copy" else {
        throw AppFailure.message("A newer clipboard copy was overwritten.")
    }
    pasteboard.clearContents()
    let empty = try ClipboardLease(text: "temporary", pasteboard: pasteboard)
    empty.restore()
    guard pasteboard.pasteboardItems?.isEmpty != false else { throw AppFailure.message("Empty clipboard was not restored.") }
    // Snapshot, then a synthetic copy replaces the clipboard before staging the result.
    pasteboard.clearContents()
    pasteboard.setString("before copy", forType: .string)
    let copyLease = try ClipboardLease(pasteboard: pasteboard)
    guard pasteboard.string(forType: .string) == "before copy" else { throw AppFailure.message("Saving the clipboard changed it.") }
    pasteboard.clearContents()
    pasteboard.setString("selected text", forType: .string)
    copyLease.claim()
    try copyLease.stage("converted text")
    guard pasteboard.string(forType: .string) == "converted text" else { throw AppFailure.message("Staging after a copy failed.") }
    copyLease.restore()
    guard pasteboard.string(forType: .string) == "before copy" else {
        throw AppFailure.message("The clipboard was not restored after a copy and paste.")
    }
    let raced = try ClipboardLease(pasteboard: pasteboard)
    pasteboard.clearContents()
    pasteboard.setString("selected text", forType: .string)
    raced.claim()
    pasteboard.clearContents()
    pasteboard.setString("new user copy", forType: .string)
    do {
        try raced.stage("converted text")
        throw AppFailure.message("Staging overwrote a newer clipboard copy.")
    } catch AppFailure.message("The clipboard changed. Try again.") {}
    raced.restore()
    guard pasteboard.string(forType: .string) == "new user copy" else {
        throw AppFailure.message("A newer clipboard copy was overwritten after a synthetic copy.")
    }
    pasteboard.setString("restore on release", forType: .string)
    var automatic: ClipboardLease? = try ClipboardLease(text: "temporary", pasteboard: pasteboard)
    guard automatic != nil, pasteboard.string(forType: .string) == "temporary" else {
        throw AppFailure.message("Automatic clipboard lease was not staged.")
    }
    automatic = nil
    guard pasteboard.string(forType: .string) == "restore on release" else {
        throw AppFailure.message("Releasing a clipboard lease did not restore its contents.")
    }
    print("Clipboard checks passed: multiple items, binary formats, Unicode, newer-copy protection, empty clipboard, idempotence, copy-then-paste staging, automatic restoration.")
}

/// Uses enabled layouts without selecting a different input source or posting keys.
func checkInstalledLayouts() throws {
    let layouts = Layouts()
    guard let english = layouts.available.first(where: { $0.id == layouts.englishID }),
          let russian = layouts.available.first(where: { $0.id == layouts.russianID }) else {
        throw AppFailure.message("Enable U.S. (or ABC) and Russian layouts first.")
    }
    // Key 5 is G/П, 49 is Space, 36 is Return, 123 is Left Arrow.
    for (layout, plain, upper) in [(english, "g", "G"), (russian, "п", "П")] {
        guard layout.typedCharacter(key: 5, shifted: false, capsLock: false) == plain,
              layout.typedCharacter(key: 5, shifted: true, capsLock: false) == upper,
              layout.typedCharacter(key: 5, shifted: false, capsLock: true) == upper,
              layout.typedCharacter(key: 49, shifted: false, capsLock: false) == " ",
              layout.typedCharacter(key: 36, shifted: false, capsLock: false) == nil,
              layout.typedCharacter(key: 123, shifted: false, capsLock: false) == nil else {
            throw AppFailure.message("Typed characters did not match the installed layout.")
        }
    }
    for (input, expected) in [("ghbdtn", "привет"), ("привет", "ghbdtn"),
                              ("GhBdTn", "ПрИвЕт"), ("ПрИвЕт", "GhBdTn"),
                              ("ghbdtn\nGhbdtn 👋", "привет\nПривет 👋")] {
        guard try layouts.conversion(for: input).text == expected else {
            throw AppFailure.message("Installed layout conversion did not match the expected keyboard positions.")
        }
    }
    do {
        _ = try layouts.conversion(for: "hello мир")
    } catch {
        print("Installed layout checks passed: typed characters with Shift/Caps Lock, both directions, mixed case, multiline text, emoji, mixed-alphabet rejection.")
        return
    }
    throw AppFailure.message("Mixed Latin/Cyrillic text must not be converted automatically.")
}
