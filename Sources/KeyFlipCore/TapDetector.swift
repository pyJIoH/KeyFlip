import Foundation

public struct Modifiers: OptionSet, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = Modifiers(rawValue: 1)
    public static let option = Modifiers(rawValue: 2)
    public static let shift = Modifiers(rawValue: 4)
    public static let control = Modifiers(rawValue: 8)
    public static let function = Modifiers(rawValue: 16)
}

/// A shortcut is a complete, brief press/release with no intervening activity.
public struct TapDetector {
    private enum State {
        case idle
        case armed(key: UInt16, action: Action, started: TimeInterval)
        case cancelled
    }
    private var state: State = .idle
    public var maximumDuration: TimeInterval = 1.0
    public init() {}
    public mutating func cancel() {
        if case .armed = state { state = .cancelled }
    }
    public mutating func reset() { state = .idle }

    public mutating func flagsChanged(key: UInt16, modifiers: Modifiers, time: TimeInterval) -> Action? {
        switch state {
        case .cancelled:
            if modifiers.isEmpty { state = .idle }
        case let .armed(armedKey, action, started):
            state = modifiers.isEmpty ? .idle : .cancelled
            if key == armedKey && modifiers.isEmpty && time >= started && time - started <= maximumDuration {
                return action
            }
        case .idle:
            if (key == 58 || key == 61) && modifiers == .option {
                state = .armed(key: key, action: .layout, started: time)
            } else if key == 59 && modifiers == .control { // kVK_Control: left only; right is 62.
                state = .armed(key: key, action: .invertCase, started: time)
            } else if !modifiers.isEmpty {
                state = .cancelled
            }
        }
        return nil
    }
}
