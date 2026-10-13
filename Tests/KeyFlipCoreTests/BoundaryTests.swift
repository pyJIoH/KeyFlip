import Foundation
import KeyFlipCore

struct BoundaryTests {
    func testTapDurationBoundaries() {
        for (elapsed, expected): (Double, Action?) in [(1, .layout), (1.001, nil), (-0.1, nil)] {
            var detector = TapDetector()
            _ = detector.flagsChanged(key: 58, modifiers: .option, time: 10)
            expectEqual(detector.flagsChanged(key: 58, modifiers: [], time: 10 + elapsed), expected)
        }
    }

    func testWrongReleaseAndRecovery() {
        var detector = TapDetector()
        _ = detector.flagsChanged(key: 58, modifiers: .option, time: 1)
        expectNil(detector.flagsChanged(key: 61, modifiers: [], time: 1.1))
        _ = detector.flagsChanged(key: 59, modifiers: .control, time: 2)
        expectEqual(detector.flagsChanged(key: 59, modifiers: [], time: 2.1), .invertCase)
    }

    func testDuplicatePressCancelsTap() {
        var detector = TapDetector()
        _ = detector.flagsChanged(key: 58, modifiers: .option, time: 1)
        expectNil(detector.flagsChanged(key: 58, modifiers: .option, time: 1.1))
        expectNil(detector.flagsChanged(key: 58, modifiers: [], time: 1.2))
        _ = detector.flagsChanged(key: 58, modifiers: .option, time: 2)
        expectEqual(detector.flagsChanged(key: 58, modifiers: [], time: 2.1), .layout)
    }

    func testResetAfterCancelledGesture() {
        var detector = TapDetector()
        _ = detector.flagsChanged(key: 58, modifiers: .option, time: 1)
        detector.cancel()
        detector.cancel()
        detector.reset() // Focus change or event tap restart without a key-up.
        _ = detector.flagsChanged(key: 59, modifiers: .control, time: 2)
        expectEqual(detector.flagsChanged(key: 59, modifiers: [], time: 2.1), .invertCase)
    }

    func testDocumentRangeOverflow() {
        expectNil(WordAtCaret.range(in: " x", documentOffset: Int.max))
        expectNil(WordAtCaret.range(in: " x", documentOffset: Int.max - 1))
        expectEqual(WordAtCaret.range(in: " x", documentOffset: Int.max - 2),
                    NSRange(location: Int.max - 1, length: 1))
    }

    func testWordLimitUsesUTF16() {
        expectEqual(WordAtCaret.range(in: String(repeating: "😀", count: 128)),
                    NSRange(location: 0, length: 256))
        expectNil(WordAtCaret.range(in: String(repeating: "😀", count: 129)))
    }

    func testUnicodeWhitespaceBoundaries() {
        expectEqual(WordAtCaret.range(in: "first\u{00A0}word\u{00A0}"), NSRange(location: 6, length: 4))
        expectNil(WordAtCaret.range(in: "word\r\n  "))
        expectNil(WordAtCaret.range(in: "word\u{2028}"))
        expectEqual(WordAtCaret.range(in: "first\r\nword"), NSRange(location: 7, length: 4))
    }

    func testFocusDepthLimit() {
        func resolve(_ depth: Int, usable: Set<Int>) -> Int? {
            FocusedEditorResolver.resolve(candidates: [1], focusedChild: { $0 + 1 },
                                         isUsable: { usable.contains($0) }, sameElement: ==,
                                         maximumDepth: depth)
        }
        expectNil(resolve(0, usable: [1]))
        expectNil(resolve(-1, usable: [1]))
        expectNil(resolve(8, usable: [9]))
        expectEqual(resolve(8, usable: [1, 8, 9]), 8)
    }

    func testFocusProviderPriority() {
        let result = FocusedEditorResolver.resolve(candidates: [1, 2], focusedChild: { _ in nil },
                                                   isUsable: { _ in true }, sameElement: ==)
        expectEqual(result, 1)
    }

    func testUsableFocusSelfCycle() {
        let result = FocusedEditorResolver.resolve(candidates: [1], focusedChild: { $0 },
                                                   isUsable: { _ in true }, sameElement: ==)
        expectEqual(result, 1)
    }

    func testWholeAlphabetsCaseRoundTrip() {
        let lower = "abcdefghijklmnopqrstuvwxyz абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
        let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
        expectEqual(Transforms.invertCase(lower), upper)
        expectEqual(Transforms.invertCase(upper), lower)
        expectEqual(Transforms.invertCase(Transforms.invertCase(lower + upper)), lower + upper)
    }

    func testMultilineAndEmptyTransforms() {
        expectEqual(Transforms.invertCase("Hello\nМИР\t123"), "hELLO\nмир\t123")
        expectEqual(Transforms.invertCase(""), "")
        expectEqual(Transforms.alphabet(of: ""), .neither)
        expectEqual(Transforms.convert("", using: ["a": "ф"]), "")
        expectEqual(Transforms.convert("a\nя 👩‍💻", using: [:]), "a\nя 👩‍💻")
    }
}
