import Foundation
import KeyFlipCore

final class TapDetectorTests {
    func testOptionTapOnEitherSide() {
        for key: UInt16 in [58, 61] {
            var detector = TapDetector()
            expectNil(detector.flagsChanged(key: key, modifiers: .option, time: 1))
            expectEqual(detector.flagsChanged(key: key, modifiers: [], time: 1.1), .layout)
        }
    }
    func testOnlyLeftControlInvertsCase() {
        var detector = TapDetector()
        expectNil(detector.flagsChanged(key: 59, modifiers: .control, time: 1))
        expectEqual(detector.flagsChanged(key: 59, modifiers: [], time: 1.1), .invertCase)
        expectNil(detector.flagsChanged(key: 62, modifiers: .control, time: 2))
        expectNil(detector.flagsChanged(key: 62, modifiers: [], time: 2.1))
        _ = detector.flagsChanged(key: 59, modifiers: .control, time: 3)
        expectEqual(detector.flagsChanged(key: 59, modifiers: [], time: 3.1), .invertCase)
    }
    func testCommandKeysDoNotTrigger() {
        for key: UInt16 in [54, 55] {
            var detector = TapDetector()
            expectNil(detector.flagsChanged(key: key, modifiers: .command, time: 1))
            expectNil(detector.flagsChanged(key: key, modifiers: [], time: 1.1))
            _ = detector.flagsChanged(key: 58, modifiers: .option, time: 2)
            expectEqual(detector.flagsChanged(key: 58, modifiers: [], time: 2.1), .layout)
        }
    }
    func testNormalTypingDoesNotConsumeTheNextTap() {
        var detector = TapDetector()
        detector.cancel() // An ordinary letter, with no modifier held.
        _ = detector.flagsChanged(key: 58, modifiers: .option, time: 1)
        expectEqual(detector.flagsChanged(key: 58, modifiers: [], time: 1.1), .layout)
    }
    func testShortcutDoesNotTriggerOnRelease() {
        let shortcuts: [(UInt16, Modifiers, Action)] = [(58, .option, .layout), (61, .option, .layout), (59, .control, .invertCase)]
        for (key, modifiers, action) in shortcuts {
            var detector = TapDetector()
            _ = detector.flagsChanged(key: key, modifiers: modifiers, time: 1)
            detector.cancel() // Option+Arrow, Control+A, a mouse click, or scrolling.
            expectNil(detector.flagsChanged(key: key, modifiers: [], time: 1.1))
            _ = detector.flagsChanged(key: key, modifiers: modifiers, time: 2)
            expectEqual(detector.flagsChanged(key: key, modifiers: [], time: 2.1), action)
        }
    }
    func testMixedModifiersAreNotTaps() {
        for releaseOptionFirst in [true, false] {
            var detector = TapDetector()
            _ = detector.flagsChanged(key: 58, modifiers: .option, time: 1)
            _ = detector.flagsChanged(key: 59, modifiers: [.control, .option], time: 1.05)
            expectNil(detector.flagsChanged(key: releaseOptionFirst ? 58 : 59,
                                           modifiers: releaseOptionFirst ? .control : .option, time: 1.1))
            expectNil(detector.flagsChanged(key: releaseOptionFirst ? 59 : 58, modifiers: [], time: 1.2))
        }
    }
    func testBothOptionKeysDoNotTrigger() {
        for first: UInt16 in [58, 61] {
            let second: UInt16 = first == 58 ? 61 : 58
            var detector = TapDetector()
            _ = detector.flagsChanged(key: first, modifiers: .option, time: 1)
            _ = detector.flagsChanged(key: second, modifiers: .option, time: 1.05)
            _ = detector.flagsChanged(key: first, modifiers: .option, time: 1.1)
            expectNil(detector.flagsChanged(key: second, modifiers: [], time: 1.2))
        }
    }
    func testBothControlKeysDoNotTrigger() {
        for first: UInt16 in [59, 62] {
            let second: UInt16 = first == 59 ? 62 : 59
            var detector = TapDetector()
            _ = detector.flagsChanged(key: first, modifiers: .control, time: 1)
            _ = detector.flagsChanged(key: second, modifiers: .control, time: 1.05)
            _ = detector.flagsChanged(key: first, modifiers: .control, time: 1.1)
            expectNil(detector.flagsChanged(key: second, modifiers: [], time: 1.2))
        }
    }
    func testLongHoldAndUnmatchedReleaseDoNotTrigger() {
        for (key, modifiers): (UInt16, Modifiers) in [(58, .option), (61, .option), (59, .control)] {
            var detector = TapDetector()
            expectNil(detector.flagsChanged(key: key, modifiers: [], time: 1))
            _ = detector.flagsChanged(key: key, modifiers: modifiers, time: 2)
            expectNil(detector.flagsChanged(key: key, modifiers: [], time: 3.5))
        }
    }
    func testResetCancelsAnArmedTap() {
        var detector = TapDetector()
        _ = detector.flagsChanged(key: 58, modifiers: .option, time: 1)
        detector.reset()
        expectNil(detector.flagsChanged(key: 58, modifiers: [], time: 1.1))
    }
    func testHeldShiftOrCommandBlocksNewHotkeys() {
        for other: Modifiers in [.shift, .command, .function] {
            for (key, modifiers): (UInt16, Modifiers) in [(58, .option), (61, .option), (59, .control)] {
                var detector = TapDetector()
                expectNil(detector.flagsChanged(key: key, modifiers: modifiers.union(other), time: 1))
                expectNil(detector.flagsChanged(key: key, modifiers: other, time: 1.1))
                expectNil(detector.flagsChanged(key: 56, modifiers: [], time: 1.2))
            }
        }
    }
    func testRepeatedAndAlternatingTaps() {
        var detector = TapDetector()
        let sequence: [(UInt16, Modifiers, Action)] = [(58, .option, .layout), (61, .option, .layout),
                                                      (59, .control, .invertCase), (59, .control, .invertCase),
                                                      (58, .option, .layout)]
        for (index, tap) in sequence.enumerated() {
            let (key, modifiers, action) = tap
            let time = Double(index)
            expectNil(detector.flagsChanged(key: key, modifiers: modifiers, time: time))
            expectEqual(detector.flagsChanged(key: key, modifiers: [], time: time + 0.1), action)
            expectNil(detector.flagsChanged(key: key, modifiers: [], time: time + 0.2))
        }
    }
}

final class WordAtCaretTests {
    func testTrailingWord() {
        expectEqual(WordAtCaret.range(in: "hello ghbdtn! "), NSRange(location: 6, length: 7))
    }
    func testRussianWord() {
        expectEqual(WordAtCaret.range(in: "привет мир"), NSRange(location: 7, length: 3))
    }
    func testUTF16EmojiPrefix() {
        expectEqual(WordAtCaret.range(in: "👩‍💻 привет"), NSRange(location: 6, length: 6))
    }
    func testJoinedEmojiInWord() {
        expectEqual(WordAtCaret.range(in: "hi👩‍💻 "), NSRange(location: 0, length: 7))
    }
    func testEmptyAndWhitespace() {
        expectNil(WordAtCaret.range(in: ""))
        expectNil(WordAtCaret.range(in: "   "))
    }
    func testNewlineAndTabDoNotReachPreviousWord() {
        expectNil(WordAtCaret.range(in: "hello\n"))
        expectNil(WordAtCaret.range(in: "hello\t"))
        expectEqual(WordAtCaret.range(in: "hello\nworld"), NSRange(location: 6, length: 5))
    }
    func testBoundedWindowOffset() {
        expectEqual(WordAtCaret.range(in: "earlier hello", documentOffset: 100), NSRange(location: 108, length: 5))
    }
    func testTruncatedWordRejected() {
        expectNil(WordAtCaret.range(in: "partialword", documentOffset: 100))
    }
    func testOversizedWordRejected() {
        expectNil(WordAtCaret.range(in: String(repeating: "x", count: 257)))
        expectEqual(WordAtCaret.range(in: String(repeating: "x", count: 256)), NSRange(location: 0, length: 256))
    }
    func testTooManyTrailingSpacesRejected() {
        expectNil(WordAtCaret.range(in: "word         "))
        expectEqual(WordAtCaret.range(in: "word        "), NSRange(location: 0, length: 4))
    }
    func testNegativeOffsetRejected() {
        expectNil(WordAtCaret.range(in: "hello", documentOffset: -1))
    }
    func testCombiningCharacters() {
        expectEqual(WordAtCaret.range(in: "e\u{301} "), NSRange(location: 0, length: 2))
    }
}

final class TransformTests {
    func testCaseInversionInBothLanguages() {
        expectEqual(Transforms.invertCase("Hello ПРИВЕТ"), "hELLO привет")
        expectEqual(Transforms.invertCase("Ёё ABC xyz"), "ёЁ abc XYZ")
    }
    func testSymbolsAndEmojiArePreserved() {
        expectEqual(Transforms.invertCase("123 !? 👩‍💻"), "123 !? 👩‍💻")
    }
    func testCaseCanChangeUnicodeLength() {
        expectEqual(Transforms.invertCase("straße"), "STRASSE")
    }
    func testAlphabetDetection() {
        expectEqual(Transforms.alphabet(of: "ghbdtn!"), .english)
        expectEqual(Transforms.alphabet(of: "Привет, ёж!"), .russian)
        expectEqual(Transforms.alphabet(of: "Hello мир"), .mixed)
        expectEqual(Transforms.alphabet(of: "123!?"), .neither)
    }
    func testMappingPreservesUnmappedCharactersAndWhitespace() {
        let mapping = ["g": "п", "h": "р", "b": "и", "d": "в", "t": "е", "n": "т"]
        expectEqual(Transforms.convert("ghbdtn 👋\n123", using: mapping), "привет 👋\n123")
    }
}
