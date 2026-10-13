import AppKit
import ApplicationServices
import Carbon
import KeyFlipCore

struct TextTarget {
    let element: AXUIElement
    let processID: pid_t
    let originalSelection: CFRange
    let range: CFRange
    let text: String
    let wasSelected: Bool
}

final class TextAccess {
    private let system = AXUIElementCreateSystemWide()
    private var preparationAttempts: [pid_t: Date] = [:]
    private var preparationStarted: [pid_t: Date] = [:]
    init() { AXUIElementSetMessagingTimeout(system, 0.5) }

    func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    func prepare(_ app: NSRunningApplication) {
        guard AXIsProcessTrusted() else { return }
        let pid = app.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        // Chromium/Electron may expose only an application shell until a client
        // requests their accessibility tree. This does not alter macOS permissions.
        let names = ["AXManualAccessibility", "AXEnhancedUserInterface"]
        if names.contains(where: { attribute($0, of: application) as? Bool == true }) {
            preparationStarted.removeValue(forKey: pid)
            return
        }
        let now = Date()
        // Electron debounces activation for two seconds. Repeated setters during
        // polling keep resetting that timer; failed/disabled activation must also
        // be retryable instead of being cached forever for the process lifetime.
        if let last = preparationAttempts[pid], now.timeIntervalSince(last) < 4 { return }
        preparationAttempts[pid] = now
        for name in names {
            // Some hosts implement the setter without advertising it as settable.
            // Unsupported native apps simply return an AX error here.
            if AXUIElementSetAttributeValue(application, name as CFString, kCFBooleanTrue) == .success {
                preparationStarted[pid] = now
                return
            }
        }
    }

    var isPreparingFocusedApplication: Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let started = preparationStarted[pid] else { return false }
        return Date().timeIntervalSince(started) < 3
    }

    func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        prepare(app)
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        func elementAttribute(_ name: String, of owner: AXUIElement) -> AXUIElement? {
            guard let value = attribute(name, of: owner), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            let element = value as! AXUIElement
            AXUIElementSetMessagingTimeout(element, 0.5)
            return element
        }
        var candidates = [application, system].compactMap { elementAttribute(kAXFocusedUIElementAttribute, of: $0) }
        if let window = elementAttribute(kAXFocusedWindowAttribute, of: application),
           let focused = elementAttribute(kAXFocusedUIElementAttribute, of: window) {
            candidates.append(focused)
        }
        return FocusedEditorResolver.resolve(
            candidates: candidates,
            focusedChild: { elementAttribute(kAXFocusedUIElementAttribute, of: $0) },
            isUsable: isEditableAndUnprotected,
            sameElement: { CFEqual($0, $1) }
        ) ?? candidates.first
    }

    func isEditableAndUnprotected(_ element: AXUIElement) -> Bool {
        guard !IsSecureEventInputEnabled(),
              let role = attribute(kAXRoleAttribute, of: element) as? String,
              ([kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role)
               || attribute("AXEditable", of: element) as? Bool == true
               || (role == kAXGroupRole && selection(of: element) != nil)),
              attribute(kAXEnabledAttribute, of: element) as? Bool != false,
              attribute(kAXSubroleAttribute, of: element) as? String != kAXSecureTextFieldSubrole,
              attribute("AXProtectedContent", of: element) as? Bool != true else { return false }
        return selection(of: element) != nil
    }

    func selection(of element: AXUIElement) -> CFRange? {
        guard let value = attribute(kAXSelectedTextRangeAttribute, of: element), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range
    }

    func read(_ range: CFRange, from element: AXUIElement) -> String? {
        guard range.location >= 0, range.length >= 0, range.length <= 100_000,
              range.location <= Int.max - range.length else { return nil }
        if let selected = selection(of: element), selected.matches(range),
           let text = attribute(kAXSelectedTextAttribute, of: element) as? String,
           text.utf16.count == range.length { return text }
        var mutableRange = range
        if let parameter = AXValueCreate(.cfRange, &mutableRange) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         parameter, &value) == .success,
               let text = value as? String, text.utf16.count == range.length { return text }
        }
        if let text = attribute(kAXValueAttribute, of: element) as? String {
            let value = text as NSString
            if range.location + range.length <= value.length {
                return value.substring(with: NSRange(location: range.location, length: range.length))
            }
        }
        return nil
    }

    func target() throws -> TextTarget {
        guard !IsSecureEventInputEnabled() else { throw TextTargetFailure.secureInput }
        guard let element = focusedElement() else { throw TextTargetFailure.unavailable("No focused editor") }
        let role = attribute(kAXRoleAttribute, of: element) as? String ?? "unknown"
        guard attribute(kAXSubroleAttribute, of: element) as? String != kAXSecureTextFieldSubrole,
              attribute("AXProtectedContent", of: element) as? Bool != true else { throw TextTargetFailure.secureInput }
        guard isEditableAndUnprotected(element), let selected = selection(of: element) else {
            throw TextTargetFailure.unavailable("\(role): text selection unavailable")
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid == NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            throw AppFailure.message("The focused app changed. Try again.")
        }
        let range: CFRange
        if selected.length > 0 {
            range = selected
        } else {
            guard selected.location > 0 else { throw TextTargetFailure.noWord }
            let start = max(0, selected.location - 4096)
            guard let preceding = read(CFRange(location: start, length: selected.location - start), from: element) else {
                throw TextTargetFailure.unavailable("\(role): text before cursor unavailable")
            }
            guard let wordRange = WordAtCaret.range(in: preceding, documentOffset: start) else { throw TextTargetFailure.noWord }
            range = CFRange(location: wordRange.location, length: wordRange.length)
        }
        guard let text = read(range, from: element), !text.isEmpty else {
            throw AppFailure.message("This editor does not expose the target text. No text was changed.")
        }
        return TextTarget(element: element, processID: pid, originalSelection: selected,
                          range: range, text: text, wasSelected: selected.length > 0)
    }

    func stillFocused(_ target: TextTarget) -> Bool {
        guard !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID,
              let element = focusedElement(), CFEqual(element, target.element) else { return false }
        return isEditableAndUnprotected(element)
    }

    @discardableResult
    func select(_ range: CFRange, in element: AXUIElement) -> Bool {
        var mutable = range
        guard let value = AXValueCreate(.cfRange, &mutable),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return false }
        // AX setters acknowledge the request before some editors publish the
        // updated selection. The replacement coordinator waits for confirmation.
        return true
    }
}

enum TextTargetFailure: LocalizedError {
    case noWord
    case secureInput
    case unavailable(String)
    var errorDescription: String? {
        switch self {
        case .noWord: return "No word before the cursor. Select text or type a word first."
        case .secureInput: return "Password fields and Secure Input are excluded."
        case let .unavailable(reason): return "This editor did not expose editable text (\(reason))."
        }
    }
}

/// Stores all eagerly readable clipboard representations; never overwrites a later copy.
final class ClipboardLease {
    private var saved: [NSPasteboardItem] = []
    private var ownedChangeCount: Int?
    private let pasteboard: NSPasteboard

    init(text: String, pasteboard: NSPasteboard = .general) throws {
        self.pasteboard = pasteboard
        let originalChangeCount = pasteboard.changeCount
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    throw AppFailure.message("The clipboard cannot be preserved right now. Try copying ordinary text first.")
                }
                copy.setData(data, forType: type)
            }
            saved.append(copy)
        }
        guard pasteboard.changeCount == originalChangeCount else {
            throw AppFailure.message("The clipboard changed. Try again.")
        }
        pasteboard.clearContents()
        if !pasteboard.setString(text, forType: .string) {
            ownedChangeCount = pasteboard.changeCount
            restore()
            throw AppFailure.message("Could not prepare the text for insertion.")
        }
        ownedChangeCount = pasteboard.changeCount
    }

    func restore() {
        guard let ownedChangeCount, pasteboard.changeCount == ownedChangeCount else { return }
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        self.ownedChangeCount = nil
    }
    deinit { restore() }
}

final class TextReplacement {
    let access: TextAccess
    var activityVersion: () -> UInt64 = { 0 }
    private(set) var busy = false
    private var pasteMethod = ""
    private var activeLease: ClipboardLease?
    init(access: TextAccess) { self.access = access }

    func shutdown() {
        activeLease?.restore()
        activeLease = nil
    }

    func replace(_ target: TextTarget, with text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !busy else { return }
        let version = activityVersion()
        guard access.stillFocused(target), target.originalSelection.matches(access.selection(of: target.element)),
              access.read(target.range, from: target.element) == target.text else {
            completion(.failure(AppFailure.message("The target changed. No text was replaced."))); return
        }
        busy = true
        guard target.originalSelection.matches(target.range) || access.select(target.range, in: target.element) else {
            busy = false
            completion(.failure(AppFailure.message("This editor does not allow selecting the recent word. Select it manually first."))); return
        }
        waitForSelection(target.range, target: target, version: version) { [self] selected in
            guard selected else {
                restoreSelectionIfUnchanged(target, version: version)
                busy = false
                completion(.failure(AppFailure.message("The editor did not confirm the word selection. No replacement was sent.")))
                return
            }
            // Web editors may publish an AX selection before their renderer has
            // finished handling it. Allow that request to settle, then revalidate.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
                insert(target, text: text, version: version, completion: completion)
            }
        }
    }

    private func insert(_ target: TextTarget, text: String, version: UInt64, completion: @escaping (Result<Void, Error>) -> Void) {
        guard activityVersion() == version, access.stillFocused(target),
              target.range.matches(access.selection(of: target.element)),
              access.read(target.range, from: target.element) == target.text else {
            busy = false
            completion(.failure(AppFailure.message("The target changed before replacement. Try again.")))
            return
        }
        // Use the editor's normal paste action, including its input events and Undo
        // handling. An AXSelectedText setter can acknowledge a write without the
        // application committing it to its document model.
        do {
            let lease = try ClipboardLease(text: text)
            activeLease = lease
            guard access.stillFocused(target), activityVersion() == version,
                  target.range.matches(access.selection(of: target.element)),
                  access.read(target.range, from: target.element) == target.text else {
                lease.restore()
                throw AppFailure.message("The target changed before pasting. Try again.")
            }
            try paste(into: target, version: version)
            verify(target, text: text, version: version, lease: lease, attempts: 20, completion: completion)
        } catch {
            activeLease?.restore()
            activeLease = nil
            restoreSelectionIfUnchanged(target, version: version)
            busy = false
            completion(.failure(error))
        }
    }

    private func waitForSelection(_ range: CFRange, target: TextTarget, version: UInt64, attempts: Int = 20,
                                  completion: @escaping (Bool) -> Void) {
        guard activityVersion() == version, access.stillFocused(target) else { completion(false); return }
        if range.matches(access.selection(of: target.element)) { completion(true); return }
        guard attempts > 1 else { completion(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [self] in
            waitForSelection(range, target: target, version: version, attempts: attempts - 1, completion: completion)
        }
    }

    private func paste(into target: TextTarget, version: UInt64) throws {
        guard activityVersion() == version, access.stillFocused(target),
              target.range.matches(access.selection(of: target.element)),
              access.read(target.range, from: target.element) == target.text else {
            throw AppFailure.message("The target changed before pasting. Try again.")
        }
        pasteMethod = "Command+V"
        try postPaste()
    }

    private func postPaste() throws {
        guard CGPreflightPostEventAccess() else {
            throw AppFailure.message("macOS is blocking keyboard insertion. Renew KeyFlip's Accessibility access, then quit and reopen KeyFlip.")
        }
        // Use normal session routing after the focus checks above. Posting to a
        // PID skips part of the normal keyboard/shortcut dispatch in some apps.
        try PasteShortcut.events().forEach { $0.post(tap: .cgSessionEventTap) }
    }

    private func restoreSelectionIfUnchanged(_ target: TextTarget, version: UInt64) {
        if activityVersion() == version, access.stillFocused(target),
           target.range.matches(access.selection(of: target.element)),
           access.read(target.range, from: target.element) == target.text {
            access.select(target.originalSelection, in: target.element)
        }
    }

    private func verify(_ target: TextTarget, text: String, version: UInt64, lease: ClipboardLease?, attempts: Int,
                        completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            let replacementRange = CFRange(location: target.range.location, length: text.utf16.count)
            guard activityVersion() == version, access.stillFocused(target) else {
                // Keep the temporary clipboard briefly available to an in-flight paste.
                let finish = {
                    lease?.restore()
                    self.activeLease = nil
                    self.busy = false
                    completion(.failure(AppFailure.message("Input changed during replacement. Check the result before continuing.")))
                }
                // Do not permit nested clipboard leases while this one is pending.
                if lease != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: finish) }
                else { finish() }
                return
            }
            if access.read(replacementRange, from: target.element) == text {
                let finalRange = target.wasSelected ? replacementRange
                    : CFRange(location: target.originalSelection.location + text.utf16.count - target.range.length, length: 0)
                // Native paste already puts the caret after the inserted word.
                // Avoid a redundant AX setter that can disturb web-editor focus.
                guard finalRange.matches(access.selection(of: target.element)) || access.select(finalRange, in: target.element) else {
                    lease?.restore(); activeLease = nil; busy = false
                    completion(.failure(AppFailure.message("Text replaced, but the editor could not restore the cursor or selection.")))
                    return
                }
                waitForSelection(finalRange, target: target, version: version) { [self] positioned in
                    lease?.restore(); activeLease = nil; busy = false
                    completion(positioned ? .success(()) : .failure(AppFailure.message("Text replaced; cursor restoration could not be confirmed.")))
                }
            } else if attempts > 1 {
                verify(target, text: text, version: version, lease: lease, attempts: attempts - 1, completion: completion)
            } else {
                lease?.restore()
                activeLease = nil
                restoreSelectionIfUnchanged(target, version: version)
                busy = false
                completion(.failure(AppFailure.message("The editor did not confirm the pasted text (\(pasteMethod)). Check the result; it will not be pasted again automatically.")))
            }
        }
    }
}

private extension CFRange {
    func matches(_ other: CFRange?) -> Bool {
        guard let other else { return false }
        return location == other.location && length == other.length
    }
}
