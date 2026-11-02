import Foundation

/// The word typed since the last caret-moving input, plus the spaces typed after it.
/// It is kept only in memory so the word can be retyped in editors that do not expose
/// their text through Accessibility. Each entry is one character, removed by one Backspace.
public struct TypedWordBuffer: Equatable {
    public struct Keystroke: Equatable {
        public let key: UInt16
        public let text: String
        public init(key: UInt16, text: String) {
            self.key = key
            self.text = text
        }
    }

    /// Same limits as `WordAtCaret`, so both paths agree on what "the last word" is.
    public static let maximumWordLength = 256
    public static let maximumTrailingSpaces = 8
    /// Used for characters that have no recorded physical key, e.g. after `ß` → `SS`.
    public static let fallbackKey: UInt16 = 0
    public static let spaceKey: UInt16 = 49

    public private(set) var word: [Keystroke] = []
    public private(set) var trailingSpaces = 0
    /// The current word grew past the limit; ignore it until the next space.
    private var overflowed = false

    public init() {}

    public var text: String { word.map(\.text).joined() }
    public var trailingText: String { String(repeating: " ", count: trailingSpaces) }
    /// Characters after the start of the word: the number of Backspaces that remove it.
    public var characterCount: Int { word.count + trailingSpaces }
    public var isConvertible: Bool { !word.isEmpty }

    public mutating func reset() {
        word = []
        trailingSpaces = 0
        overflowed = false
    }

    /// Records a keystroke that inserted `text`. Anything other than one character
    /// means the editor's contents can no longer be predicted.
    public mutating func insert(key: UInt16, text: String) {
        guard text.count == 1, let character = text.first else { reset(); return }
        if character == " " {
            if overflowed { reset(); return }
            // A space with no tracked word before it says nothing about the editor.
            guard !word.isEmpty else { return }
            trailingSpaces += 1
            if trailingSpaces > Self.maximumTrailingSpaces { reset() }
            return
        }
        if character.isWhitespace { reset(); return }
        if trailingSpaces > 0 {
            word = []
            trailingSpaces = 0
        }
        guard !overflowed else { return }
        word.append(Keystroke(key: key, text: text))
        if self.text.utf16.count > Self.maximumWordLength {
            word = []
            overflowed = true
        }
    }

    public mutating func deleteBackward() {
        if trailingSpaces > 0 { trailingSpaces -= 1 }
        else if !word.isEmpty { word.removeLast() }
    }

    /// Physical keys to send with `replacement`, one per character. Layout conversion
    /// keeps key positions; other transformations may change the character count.
    public func keys(for replacement: String) -> [UInt16] {
        let count = replacement.count
        let wordKeys = count == word.count ? word.map(\.key) : Array(repeating: Self.fallbackKey, count: count)
        return wordKeys + Array(repeating: Self.spaceKey, count: trailingSpaces)
    }

    /// Records that the word has been retyped as `replacement`; trailing spaces are kept.
    public mutating func replaceWord(with replacement: String) {
        let keys = self.keys(for: replacement)
        word = replacement.enumerated().map { index, character in
            Keystroke(key: keys[index], text: String(character))
        }
        overflowed = false
        if word.isEmpty { reset() }
    }

    /// Whether an editor's text before the caret ends with exactly this word and its
    /// spaces, starting at a word boundary. `precedingText` should include at least
    /// one character before the word unless it starts at the beginning of the document.
    public func matches(precedingText: String, startsDocument: Bool) -> Bool {
        guard isConvertible else { return false }
        let editor = Array(precedingText.utf16)
        let typed = Array((text + trailingText).utf16)
        guard editor.count >= typed.count else { return false }
        // HTML editors store a trailing typed space as a no-break space.
        let tail = editor.suffix(typed.count)
        guard zip(tail, typed).allSatisfy({ $0 == $1 || ($1 == 0x20 && $0 == 0xA0) }) else { return false }
        guard editor.count > typed.count else { return startsDocument }
        // A surrogate half is part of a non-whitespace character.
        guard let boundary = Unicode.Scalar(editor[editor.count - typed.count - 1]) else { return false }
        return Character(boundary).isWhitespace
    }
}

public enum CopiedSelection {
    /// Code editors such as VS Code, JetBrains IDEs, and Sublime Text copy the whole
    /// current line when nothing is selected. That must not be pasted back as a
    /// "converted selection", so a single line ending in a line break is rejected.
    public static func isLikelyWholeLineCopy(_ text: String) -> Bool {
        guard let last = text.last, last.isNewline else { return false }
        return !text.dropLast().contains(where: \.isNewline)
    }
}
