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
    /// The word being typed, in memory only, for editors that hide their text.
    private var typed = TypedWordBuffer()
    private var typedPID: pid_t?
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
        typed.reset()
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
        if replacement.busy { detector.reset(); typed.reset(); return }
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
        switch event.type {
        case .keyDown: recordTyping(event)
        case .scrollWheel: break // Scrolling does not move the caret.
        default: typed.reset() // A click can move the caret or focus.
        }
        detector.cancel()
    }

    /// Tracks what a key press inserted. Anything that may move the caret, select text,
    /// or run a command makes the editor's contents unpredictable, so it clears the word.
    private func recordTyping(_ event: InputEvent) {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if pid != typedPID {
            typed.reset()
            typedPID = pid
        }
        guard event.modifiers.isDisjoint(with: [.command, .control, .option]) else { typed.reset(); return }
        if event.key == UInt16(kVK_Delete) { typed.deleteBackward(); return }
        guard let text = layouts.typedCharacter(key: event.key, shifted: event.modifiers.contains(.shift),
                                                capsLock: event.capsLock) else { typed.reset(); return }
        typed.insert(key: event.key, text: text)
    }

    private var hasUsableTypedWord: Bool {
        guard typed.isConvertible, let app = NSWorkspace.shared.frontmostApplication else { return false }
        return app.processIdentifier == typedPID && !AppCategories.forwardsKeys(app)
    }

    /// Strategies, in order:
    /// 1. A word typed just now: Backspace and retype it. Works in any editor that
    ///    accepts typing; used unless Accessibility shows different text before the caret.
    /// 2. Accessibility: read the selection or the word before the caret, then paste.
    /// 3. A selection the editor does not expose: copy, convert, and paste it.
    /// 4. Otherwise, only switch the input source.
    private func perform(_ action: Action, retriesRemaining: Int = 15) {
        let typedWord = hasUsableTypedWord
        if typedWord {
            switch access.probeCaret(for: typed) {
            case .matches, .unavailable: retypeTypedWord(action); return
            case .completionSelected: retypeTypedWord(action, extraDeletions: 1); return
            case .secure, .contradicts: break
            }
        }
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
                    self.typed.reset()
                    do {
                        if let destination { try self.layouts.select(destination) }
                        self.status = action == .layout ? "Layout converted." : "Letter case inverted."
                    } catch { self.status = error.localizedDescription }
                case .failure(ReplacementFailure.selectionRejected) where typedWord && self.hasUsableTypedWord:
                    self.retypeTypedWord(action)
                    return
                case let .failure(error):
                    self.status = error.localizedDescription
                    NSSound.beep()
                }
                self.onStateChange?()
            }
        } catch TextTargetFailure.noWord {
            if typedWord { retypeTypedWord(action); return }
            if retryWhileEditorPrepares(action, retriesRemaining: retriesRemaining) { return }
            do {
                if action == .layout { try layouts.toggle(); status = "Keyboard layout switched." }
                else { status = "Select text or put the cursor after a word." }
            } catch { status = error.localizedDescription }
            onStateChange?()
        } catch TextTargetFailure.unavailable(let reason) {
            if typedWord { retypeTypedWord(action); return }
            if retryWhileEditorPrepares(action, retriesRemaining: retriesRemaining) { return }
            replaceCopiedSelection(action, reason: reason)
        } catch {
            status = error.localizedDescription
            NSSound.beep()
            onStateChange?()
        }
    }

    private func transform(_ text: String, for action: Action) throws -> (text: String, destination: KeyboardLayout?) {
        switch action {
        case .invertCase: return (Transforms.invertCase(text), nil)
        case .layout:
            let conversion = try layouts.conversion(for: text)
            return (conversion.text, conversion.target)
        }
    }

    private func retypeTypedWord(_ action: Action, extraDeletions: Int = 0) {
        let word = typed.text
        let output: String
        let destination: KeyboardLayout?
        do { (output, destination) = try transform(word, for: action) } catch {
            status = error.localizedDescription
            NSSound.beep()
            onStateChange?()
            return
        }
        // Switch first, for the few consumers that read key codes instead of characters.
        var layoutError: Error?
        if let destination {
            do { try layouts.select(destination) } catch { layoutError = error }
        }
        guard output != word else {
            status = layoutError?.localizedDescription ?? "No letters needed changing."
            onStateChange?()
            return
        }
        let version = activity
        replacement.retype(deleting: typed.characterCount + extraDeletions, with: output + typed.trailingText,
                           keys: typed.keys(for: output)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                // Allow tapping again to undo, unless other input arrived meanwhile.
                if self.activity == version { self.typed.replaceWord(with: output) } else { self.typed.reset() }
                self.status = layoutError?.localizedDescription
                    ?? (action == .layout ? "Layout converted." : "Letter case inverted.")
            case let .failure(error):
                self.typed.reset()
                self.status = error.localizedDescription
                NSSound.beep()
            }
            self.onStateChange?()
        }
    }

    private func replaceCopiedSelection(_ action: Action, reason: String) {
        // Accessibility may report an empty selection even when it cannot read the text.
        guard AppCategories.allowsClipboardFallback(NSWorkspace.shared.frontmostApplication),
              access.knownSelectionLength() != 0 else {
            switchLayoutWithoutText(action, reason: reason)
            return
        }
        var destination: KeyboardLayout?
        replacement.replaceSelectionUsingClipboard(transform: { [unowned self] text in
            let result = try transform(text, for: action)
            destination = result.destination
            return result.text
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.nothingCopied):
                self.switchLayoutWithoutText(action, reason: reason)
                return
            case let .success(outcome):
                self.typed.reset()
                do {
                    if let destination { try self.layouts.select(destination) }
                    self.status = outcome == .unchanged ? "No letters needed changing."
                        : action == .layout ? "Layout converted." : "Letter case inverted."
                } catch { self.status = error.localizedDescription }
            case let .failure(error):
                self.status = error.localizedDescription
                NSSound.beep()
            }
            self.onStateChange?()
        }
    }

    private func switchLayoutWithoutText(_ action: Action, reason: String) {
        do {
            if action == .layout {
                try layouts.toggle()
                status = "Keyboard layout switched; text was not changed (\(reason))."
            } else { status = "Cannot read this editor's selection (\(reason))."; NSSound.beep() }
        } catch { status = error.localizedDescription }
        onStateChange?()
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
