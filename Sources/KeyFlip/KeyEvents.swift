import AppKit
import Carbon
import IOKit.hidsystem

/// Synthetic keyboard events, tagged so EventMonitor ignores KeyFlip's own input.
enum KeyEvents {
    /// Real Command-<key> events, including the device-specific left Command bit.
    /// Some event consumers reconstruct modifiers from those low bits, rather
    /// than trusting maskCommand alone. Do not synthesize Command keyDown events:
    /// a real modifier key transition is flagsChanged, not an ordinary keyDown.
    static func command(_ key: Int) throws -> [CGEvent] {
        try press(CGKeyCode(key), flags: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | UInt64(NX_DEVICELCMDKEYMASK)))
    }

    static func paste() throws -> [CGEvent] { try command(kVK_ANSI_V) }
    static func copy() throws -> [CGEvent] { try command(kVK_ANSI_C) }

    /// One Backspace press per character to remove.
    static func backspaces(_ count: Int) throws -> [CGEvent] {
        try (0..<max(0, count)).flatMap { _ in try press(CGKeyCode(kVK_Delete), flags: []) }
    }

    /// One key press per character. Each event carries its character, so the result
    /// does not depend on the input source the receiving application is using.
    /// The physical key is sent as well for consumers that only read key codes.
    static func typing(_ text: String, keys: [UInt16]) throws -> [CGEvent] {
        try text.enumerated().flatMap { index, character -> [CGEvent] in
            let key = index < keys.count ? keys[index] : 0
            let events = try press(CGKeyCode(key), flags: [])
            let units = Array(String(character).utf16)
            events.forEach { $0.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units) }
            return events
        }
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags) throws -> [CGEvent] {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw AppFailure.message("Cannot create keyboard events.")
        }
        let events = [true, false].compactMap { down -> CGEvent? in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return nil }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: injectedEventTag)
            return event
        }
        guard events.count == 2 else { throw AppFailure.message("Cannot create keyboard events.") }
        return events
    }
}

/// Applications whose text input needs different handling.
enum AppCategories {
    /// Selected terminal text is usually output: pasting a converted copy would insert
    /// it at the prompt instead of replacing the selection.
    private static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "io.alacritty", "org.alacritty",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "dev.warp.Warp-Stable", "co.zeit.hyper",
        "com.mitchellh.ghostty", "org.tabby", "com.raphaelamorim.rio"
    ]
    /// Virtual machines and remote desktops forward keys to another system with its own
    /// input source; retyping or Command shortcuts would act inside that system.
    private static let keyForwarding: Set<String> = [
        "com.parallels.desktop.console", "com.vmware.fusion", "com.utmapp.UTM", "org.virtualbox.app.VirtualBoxVM",
        "com.microsoft.rdc.macos", "com.citrix.receiver.icaviewer.mac", "com.apple.ScreenSharing",
        "com.p5sys.jump.mac.viewer", "com.teamviewer.TeamViewer", "com.realvnc.vncviewer", "com.philandro.anydesk"
    ]

    static func forwardsKeys(_ app: NSRunningApplication?) -> Bool {
        keyForwarding.contains(app?.bundleIdentifier ?? "")
    }

    static func allowsClipboardFallback(_ app: NSRunningApplication?) -> Bool {
        let id = app?.bundleIdentifier ?? ""
        return !terminals.contains(id) && !keyForwarding.contains(id)
    }
}
