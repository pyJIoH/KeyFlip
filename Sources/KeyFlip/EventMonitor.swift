import AppKit
import Carbon
import KeyFlipCore

let injectedEventTag: Int64 = 0x4B_46_4C_49_50

struct InputEvent {
    let type: CGEventType
    let key: UInt16
    let modifiers: Modifiers
    let capsLock: Bool
    let time: TimeInterval
}

final class EventMonitor {
    var onEvent: ((InputEvent) -> Void)?
    var onInterruption: (() -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var running: Bool { tap.map(CGEvent.tapIsEnabled) ?? false }

    func start() -> Bool {
        stop()
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<EventMonitor>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { monitor.onInterruption?() }
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard event.getIntegerValueField(.eventSourceUserData) != injectedEventTag else { return Unmanaged.passUnretained(event) }
            var modifiers: Modifiers = []
            if event.flags.contains(.maskCommand) { modifiers.insert(.command) }
            if event.flags.contains(.maskAlternate) { modifiers.insert(.option) }
            if event.flags.contains(.maskShift) { modifiers.insert(.shift) }
            if event.flags.contains(.maskControl) { modifiers.insert(.control) }
            if event.flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
            let input = InputEvent(type: type, key: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                                   modifiers: modifiers,
                                   capsLock: event.flags.contains(.maskAlphaShift),
                                   time: Double(event.timestamp) / 1_000_000_000)
            DispatchQueue.main.async { monitor.onEvent?(input) }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                         eventsOfInterest: mask, callback: callback,
                                         userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }
}
