import AppKit
import Carbon
import ServiceManagement
import SwiftUI
import KeyFlipCore

final class AppModel: ObservableObject {
    @Published var enabled = true
    @Published var accessibilityGranted = false
    @Published var monitoringGranted = false
    @Published var running = false
    @Published var status = "Starting…"
    @Published var availableLayouts: [KeyboardLayout] = []
    @Published var englishID = ""
    @Published var russianID = ""
    @Published var launchAtLogin = false
    @Published var editorName = "your editor"
    @Published var testApplications: [NSRunningApplication] = []
    @Published var testApplicationPID: pid_t = 0
    @Published var shortcutStatus = "No shortcut detected yet."
    @Published var currentLayoutName = ""
    var onStateChange: (() -> Void)?

    let layouts = Layouts()
    private let access = TextAccess()
    private let monitor = EventMonitor()
    private lazy var replacement = TextReplacement(access: access)
    private var detector = TapDetector()
    private var lastExternalApplication: NSRunningApplication?
    private var activity: UInt64 = 0
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var secureInputWasActive = false

    func start() {
        rememberEditor(NSWorkspace.shared.frontmostApplication)
        replacement.activityVersion = { [weak self] in self?.activity ?? 0 }
        monitor.onEvent = { [weak self] in self?.handle($0) }
        monitor.onInterruption = { [weak self] in self?.invalidateContext() }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                     object: nil, queue: .main) { [weak self] note in
            self?.invalidateContext()
            self?.rememberEditor(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        refreshLayouts()
        refreshPermissions()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshPermissions()
            self.currentLayoutName = self.layouts.available.first(where: { $0.id == self.layouts.currentID })?.name ?? "Other layout"
            let secure = IsSecureEventInputEnabled()
            if secure != self.secureInputWasActive {
                self.invalidateContext()
                self.secureInputWasActive = secure
                self.status = secure ? "Paused while Secure Input is active." : "Ready — tap Option or left Control alone."
                self.onStateChange?()
            }
        }
    }

    func shutdown() {
        timer?.invalidate()
        monitor.stop()
        replacement.shutdown()
        invalidateContext()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func invalidateContext() {
        activity &+= 1
        detector.reset()
    }

    private func rememberEditor(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular else { return }
        lastExternalApplication = application
        editorName = application.localizedName ?? "your editor"
        access.prepare(application)
    }

    /// Visible diagnostic controls exercise the same pipeline as modifier taps.
    func applyInEditor(_ action: Action) {
        guard enabled, accessibilityGranted else { status = "Enable KeyFlip and Accessibility access first."; return }
        rememberEditor(NSWorkspace.shared.frontmostApplication)
        let selectedApp = testApplicationPID == 0 ? lastExternalApplication : NSRunningApplication(processIdentifier: testApplicationPID)
        guard let app = selectedApp, !app.isTerminated else { status = "Open an editor and select some text first."; return }
        app.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            self.perform(action)
        }
    }

    func toggleEnabled() {
        enabled.toggle()
        invalidateContext()
        if !enabled { monitor.stop() }
        refreshPermissions()
        status = enabled ? (running ? "Ready — tap Option or left Control alone." : "Permissions are needed to start.") : "Paused."
        onStateChange?()
    }

    func refreshLayouts() {
        layouts.reload()
        availableLayouts = layouts.available
        englishID = layouts.englishID
        russianID = layouts.russianID
        launchAtLogin = SMAppService.mainApp.status == .enabled
        testApplications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        if testApplicationPID != 0, !testApplications.contains(where: { $0.processIdentifier == testApplicationPID }) {
            testApplicationPID = 0
        }
    }

    func saveLayouts() {
        layouts.englishID = englishID
        layouts.russianID = russianID
        invalidateContext()
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        monitoringGranted = CGPreflightListenEventAccess()
        if enabled && accessibilityGranted && monitoringGranted {
            if !monitor.running {
                running = monitor.start()
                status = running ? "Ready — tap Option or left Control alone." : "Could not start the keyboard listener. Quit and reopen KeyFlip."
            } else { running = true }
        } else {
            if monitor.running { monitor.stop(); invalidateContext() }
            running = false
            if enabled { status = "Grant Accessibility and Input Monitoring access to start." }
        }
        onStateChange?()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestPostEventAccess()
    }

    func requestMonitoring() { _ = CGRequestListenEventAccess() }

    func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if value && !launchAtLogin { status = "Allow KeyFlip in macOS Login Items settings." }
        } catch { status = "Login item: \(error.localizedDescription)" }
    }

    private func handle(_ event: InputEvent) {
        guard enabled else { return }
        activity &+= 1
        if IsSecureEventInputEnabled() { invalidateContext(); return }
        if replacement.busy { detector.reset(); return }
        if event.type == .flagsChanged {
            if let action = detector.flagsChanged(key: event.key, modifiers: event.modifiers, time: event.time) {
                shortcutStatus = action == .layout ? "Option tap detected." : "Left Control tap detected."
                // Let the editor receive the modifier release before querying its
                // selection or posting the replacement shortcut.
                let version = activity
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    guard let self, self.activity == version, self.enabled else { return }
                    self.perform(action)
                }
            }
            return
        }
        detector.cancel()
    }

    private func perform(_ action: Action, retriesRemaining: Int = 15) {
        do {
            let target = try access.target()
            let output: String
            let destination: KeyboardLayout?
            switch action {
            case .invertCase: output = Transforms.invertCase(target.text); destination = nil
            case .layout:
                let conversion = try layouts.conversion(for: target.text)
                output = conversion.text
                destination = conversion.target
            }
            if output == target.text {
                if let destination { try layouts.select(destination) }
                status = "No letters needed changing."
                return
            }
            replacement.replace(target, with: output) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    do {
                        if let destination { try self.layouts.select(destination) }
                        self.status = action == .layout ? "Layout converted." : "Letter case inverted."
                    } catch { self.status = error.localizedDescription }
                case let .failure(error):
                    self.status = error.localizedDescription
                    NSSound.beep()
                }
                self.onStateChange?()
            }
        } catch TextTargetFailure.noWord {
            if retryWhileEditorPrepares(action, retriesRemaining: retriesRemaining) { return }
            do {
                if action == .layout { try layouts.toggle(); status = "Keyboard layout switched." }
                else { status = "Select text or put the cursor after a word." }
            } catch { status = error.localizedDescription }
            onStateChange?()
        } catch TextTargetFailure.unavailable(let reason) {
            if retryWhileEditorPrepares(action, retriesRemaining: retriesRemaining) { return }
            do {
                if action == .layout {
                    try layouts.toggle()
                    status = "Keyboard layout switched; text was not changed (\(reason))."
                } else { status = "Cannot read this editor's selection (\(reason))."; NSSound.beep() }
            } catch { status = error.localizedDescription }
            onStateChange?()
        } catch {
            status = error.localizedDescription
            NSSound.beep()
            onStateChange?()
        }
    }

    private func retryWhileEditorPrepares(_ action: Action, retriesRemaining: Int) -> Bool {
        guard access.isPreparingFocusedApplication, retriesRemaining > 0 else { return false }
        let version = activity
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        status = "Waiting for the editor's accessibility support…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.enabled, self.activity == version,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            self.perform(action, retriesRemaining: retriesRemaining - 1)
        }
        return true
    }
}
