import Foundation

/// Finds a complete word in a bounded slice ending at the insertion point.
/// All returned offsets are UTF-16, as required by macOS Accessibility.
public enum WordAtCaret {
    public static func range(in precedingText: String, documentOffset: Int = 0) -> NSRange? {
        guard documentOffset >= 0 else { return nil }
        var end = precedingText.endIndex
        var spaces = 0
        while end > precedingText.startIndex {
            let previous = precedingText.index(before: end)
            let character = precedingText[previous]
            guard character.isWhitespace else { break }
            if character.isNewline || character == "\t" { return nil }
            spaces += 1
            if spaces > 8 { return nil }
            end = previous
        }
        guard end > precedingText.startIndex else { return nil }
        var start = end
        while start > precedingText.startIndex {
            let previous = precedingText.index(before: start)
            if precedingText[previous].isWhitespace { break }
            start = previous
        }
        // Do not return a clipped tail of a word that started before the slice.
        guard start != precedingText.startIndex || documentOffset == 0 else { return nil }
        let range = NSRange(start..<end, in: precedingText)
        guard range.length > 0, range.length <= 256,
              documentOffset <= Int.max - range.location - range.length else { return nil }
        return NSRange(location: documentOffset + range.location, length: range.length)
    }
}
