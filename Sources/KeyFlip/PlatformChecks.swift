import AppKit
import Carbon
import IOKit.hidsystem

/// Construct and inspect events only; never post keys or inspect another app.
func checkPasteShortcut() throws {
    let events = try PasteShortcut.events()
    guard events.count == 2, events[0].type == .keyDown, events[1].type == .keyUp else {
        throw AppFailure.message("Paste must contain exactly V down and V up.")
    }
    let expectedFlags = CGEventFlags.maskCommand.rawValue | UInt64(NX_DEVICELCMDKEYMASK)
    for event in events {
        guard event.getIntegerValueField(.keyboardEventKeycode) == kVK_ANSI_V,
              event.flags.rawValue == expectedFlags,
              event.getIntegerValueField(.eventSourceUserData) == injectedEventTag,
              NSEvent(cgEvent: event)?.modifierFlags.contains(.command) == true else {
            throw AppFailure.message("Paste event lost its key, Command flags, or loop-prevention tag.")
        }
    }
    print("Paste event checks passed: V down/up, Command + left-device flag, event tags, AppKit modifier interpretation. No events posted.")
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
    pasteboard.setString("restore on release", forType: .string)
    var automatic: ClipboardLease? = try ClipboardLease(text: "temporary", pasteboard: pasteboard)
    guard automatic != nil, pasteboard.string(forType: .string) == "temporary" else {
        throw AppFailure.message("Automatic clipboard lease was not staged.")
    }
    automatic = nil
    guard pasteboard.string(forType: .string) == "restore on release" else {
        throw AppFailure.message("Releasing a clipboard lease did not restore its contents.")
    }
    print("Clipboard checks passed: multiple items, binary formats, Unicode, newer-copy protection, empty clipboard, idempotence, automatic restoration.")
}

/// Uses enabled layouts without selecting a different input source or posting keys.
func checkInstalledLayouts() throws {
    let layouts = Layouts()
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
        print("Installed layout checks passed: both directions, mixed case, multiline text, emoji, mixed-alphabet rejection.")
        return
    }
    throw AppFailure.message("Mixed Latin/Cyrillic text must not be converted automatically.")
}
