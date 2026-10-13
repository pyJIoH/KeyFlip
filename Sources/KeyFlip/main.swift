import AppKit
import SwiftUI
import Carbon
import KeyFlipCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private let toggleItem = NSMenuItem(title: "Pause", action: #selector(toggle), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.keyflip.mac")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: [.activateIgnoringOtherApps])
            NSApplication.shared.terminate(nil)
            return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: "KeyFlip")
        let menu = NSMenu()
        let title = NSMenuItem(title: "KeyFlip · English ↔ Russian", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(NSMenuItem(title: "⌥  Convert layout     Left ⌃  Invert case", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(statusLine)
        menu.addItem(.separator())
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit KeyFlip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        model.onStateChange = { [weak self] in self?.updateMenu() }
        model.start()
        if !UserDefaults.standard.bool(forKey: "hasOpened") || !model.accessibilityGranted || !model.monitoringGranted {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasOpened")
        }
    }

    private func updateMenu() {
        toggleItem.title = model.enabled ? "Pause" : "Resume"
        statusLine.title = model.status
        statusItem.button?.appearsDisabled = !model.running
        statusItem.button?.toolTip = "KeyFlip — \(model.status)"
    }

    @objc func toggle() { model.toggleEnabled() }
    @objc func showSettings() {
        model.refreshLayouts()
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "KeyFlip \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}

if CommandLine.arguments.contains("--check-paste-events") {
    do { try checkPasteShortcut(); exit(0) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

if CommandLine.arguments.contains("--diagnose") {
    let layouts = Layouts()
    let result: [String: Any] = [
        "accessibility": AXIsProcessTrusted(),
        "postEvents": CGPreflightPostEventAccess(),
        "inputMonitoring": CGPreflightListenEventAccess(),
        "secureInput": IsSecureEventInputEnabled(),
        "layouts": layouts.available.map { ["id": $0.id, "name": $0.name, "language": $0.language] },
        "currentLayout": layouts.currentID ?? "unknown"
    ]
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
} else if CommandLine.arguments.contains("--check-clipboard") {
    do { try checkClipboardIsolation() }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--check-layouts") {
    do { try checkInstalledLayouts() }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
