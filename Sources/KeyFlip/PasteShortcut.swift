import AppKit
import Carbon
import IOKit.hidsystem

enum PasteShortcut {
    /// Real Command-V key events, including the device-specific left Command bit.
    /// Some event consumers reconstruct modifiers from those low bits, rather
    /// than trusting maskCommand alone. Do not synthesize Command keyDown events:
    /// a real modifier key transition is flagsChanged, not an ordinary keyDown.
    static func events() throws -> [CGEvent] {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw AppFailure.message("Cannot create keyboard events.")
        }
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | UInt64(NX_DEVICELCMDKEYMASK))
        let events = [true, false].compactMap { down -> CGEvent? in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down) else { return nil }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: injectedEventTag)
            return event
        }
        guard events.count == 2 else { throw AppFailure.message("Cannot create the paste shortcut.") }
        return events
    }
}
