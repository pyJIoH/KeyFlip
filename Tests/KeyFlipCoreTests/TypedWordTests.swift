import Foundation
import KeyFlipCore

struct TypedWordTests {
    private func typed(_ text: String) -> TypedWordBuffer {
        var buffer = TypedWordBuffer()
        for (index, character) in text.enumerated() {
            buffer.insert(key: character == " " ? 49 : UInt16(index), text: String(character))
        }
        return buffer
    }

    func testWordAndTrailingSpaces() {
        var buffer = typed("ghbdtn")
        expectEqual(buffer.text, "ghbdtn")
        expectEqual(buffer.characterCount, 6)
        expectEqual(buffer.isConvertible, true)
        buffer.insert(key: 49, text: " ")
        buffer.insert(key: 49, text: " ")
        expectEqual(buffer.text, "ghbdtn")
        expectEqual(buffer.trailingText, "  ")
        expectEqual(buffer.characterCount, 8)
        buffer.insert(key: 5, text: "x")
        expectEqual(buffer.text, "x")
        expectEqual(buffer.trailingSpaces, 0)
    }

    func testBackspaceRemovesSpacesThenLetters() {
        var buffer = typed("abc  ")
        buffer.deleteBackward()
        expectEqual(buffer.characterCount, 4)
        buffer.deleteBackward()
        buffer.deleteBackward()
        expectEqual(buffer.text, "ab")
        expectEqual(buffer.trailingSpaces, 0)
        buffer.deleteBackward()
        buffer.deleteBackward()
        expectEqual(buffer.isConvertible, false)
        buffer.deleteBackward() // Deleting text from before the tracked word.
        expectEqual(buffer, TypedWordBuffer())
        buffer.insert(key: 0, text: "q")
        expectEqual(buffer.text, "q")
    }

    func testLeadingSpacesAndOtherWhitespace() {
        expectEqual(typed("   "), TypedWordBuffer())
        expectEqual(typed(" a").text, "a")
        for separator in ["\t", "\n", "\u{00A0}"] {
            var buffer = typed("word")
            buffer.insert(key: 0, text: separator)
            expectEqual(buffer, TypedWordBuffer())
        }
        var buffer = typed("word")
        buffer.insert(key: 0, text: "ab")
        expectEqual(buffer, TypedWordBuffer())
        buffer = typed("word")
        buffer.insert(key: 0, text: "")
        expectEqual(buffer, TypedWordBuffer())
    }

    func testTrailingSpaceLimit() {
        expectEqual(typed("word" + String(repeating: " ", count: 8)).trailingSpaces, 8)
        expectEqual(typed("word" + String(repeating: " ", count: 9)), TypedWordBuffer())
    }

    func testOverflowWaitsForNextWord() {
        var buffer = typed(String(repeating: "a", count: 256))
        expectEqual(buffer.characterCount, 256)
        buffer.insert(key: 0, text: "a")
        expectEqual(buffer.isConvertible, false)
        buffer.insert(key: 0, text: "b") // Still the clipped tail of the long word.
        buffer.deleteBackward()
        expectEqual(buffer.isConvertible, false)
        buffer.insert(key: 49, text: " ")
        buffer.insert(key: 0, text: "c")
        expectEqual(buffer.text, "c")
    }

    func testReplacementKeepsKeysAndSpaces() {
        var buffer = TypedWordBuffer()
        buffer.insert(key: 5, text: "g")
        buffer.insert(key: 4, text: "h")
        buffer.insert(key: 49, text: " ")
        expectEqual(buffer.keys(for: "пр"), [5, 4, 49])
        buffer.replaceWord(with: "пр")
        expectEqual(buffer.text, "пр")
        expectEqual(buffer.trailingText, " ")
        expectEqual(buffer.word.map(\.key), [5, 4])
        expectEqual(buffer.keys(for: "SSx"), [0, 0, 0, 49])
        buffer.replaceWord(with: "SSx")
        expectEqual(buffer.characterCount, 4)
        buffer.replaceWord(with: "")
        expectEqual(buffer, TypedWordBuffer())
    }

    func testEditorTextMatching() {
        let buffer = typed("ghbdtn ")
        expectEqual(buffer.matches(precedingText: "first ghbdtn ", startsDocument: false), true)
        expectEqual(buffer.matches(precedingText: "\nghbdtn ", startsDocument: false), true)
        expectEqual(buffer.matches(precedingText: "ghbdtn ", startsDocument: true), true)
        expectEqual(buffer.matches(precedingText: "ghbdtn ", startsDocument: false), false)
        expectEqual(buffer.matches(precedingText: "first ghbdtn\u{00A0}", startsDocument: false), true)
        // Typed into the end of an existing word: Accessibility sees the whole word.
        expectEqual(buffer.matches(precedingText: "xghbdtn ", startsDocument: false), false)
        expectEqual(buffer.matches(precedingText: "😀ghbdtn ", startsDocument: false), false)
        expectEqual(buffer.matches(precedingText: "first ghbdtn", startsDocument: false), false)
        expectEqual(buffer.matches(precedingText: "first ghbdtx ", startsDocument: false), false)
        expectEqual(buffer.matches(precedingText: "", startsDocument: true), false)
        expectEqual(TypedWordBuffer().matches(precedingText: "", startsDocument: true), false)
    }

    func testWholeLineCopyDetection() {
        expectEqual(CopiedSelection.isLikelyWholeLineCopy("let x = 1\n"), true)
        expectEqual(CopiedSelection.isLikelyWholeLineCopy("let x = 1\r\n"), true)
        expectEqual(CopiedSelection.isLikelyWholeLineCopy("\n"), true)
        expectEqual(CopiedSelection.isLikelyWholeLineCopy("ghbdtn"), false)
        expectEqual(CopiedSelection.isLikelyWholeLineCopy("one\ntwo\n"), false)
        expectEqual(CopiedSelection.isLikelyWholeLineCopy("one\ntwo"), false)
        expectEqual(CopiedSelection.isLikelyWholeLineCopy(""), false)
    }
}
