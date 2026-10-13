import Foundation

// Dependency-free runner: no XCTest runtime or full Xcode installation required.
private var failures = 0
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: String = #filePath, line: UInt = #line) {
    if actual != expected {
        failures += 1
        print("FAIL \(file):\(line): expected \(expected), got \(actual)")
    }
}
func expectNil<T>(_ actual: T?, file: String = #filePath, line: UInt = #line) {
    if let actual {
        failures += 1
        print("FAIL \(file):\(line): expected nil, got \(actual)")
    }
}

let taps = TapDetectorTests()
let words = WordAtCaretTests()
let transforms = TransformTests()
let focus = FocusedEditorTests()
let boundary = BoundaryTests()
let cases: [(String, () -> Void)] = [
    ("Web shell does not hide the system-focused editor", focus.testShellDoesNotHideSystemEditor),
    ("Resolve nested focused editor", focus.testDeepestFocusedEditorWins),
    ("Focus cycles do not hide other providers", focus.testCyclesDoNotHideOtherProviders),
    ("Reject unfocused and unreadable elements", focus.testRejectsUnfocusedAndUnreadableElements),
    ("Either Option converts layout", taps.testOptionTapOnEitherSide),
    ("Only left Control inverts case", taps.testOnlyLeftControlInvertsCase),
    ("Command keys ignored", taps.testCommandKeysDoNotTrigger),
    ("Tap after normal typing", taps.testNormalTypingDoesNotConsumeTheNextTap),
    ("Shortcut cancellation", taps.testShortcutDoesNotTriggerOnRelease),
    ("Mixed modifiers", taps.testMixedModifiersAreNotTaps),
    ("Both Option keys cancel", taps.testBothOptionKeysDoNotTrigger),
    ("Both Control keys cancel", taps.testBothControlKeysDoNotTrigger),
    ("Long hold and unmatched release", taps.testLongHoldAndUnmatchedReleaseDoNotTrigger),
    ("Reset an armed tap", taps.testResetCancelsAnArmedTap),
    ("Held modifiers block hotkeys", taps.testHeldShiftOrCommandBlocksNewHotkeys),
    ("Repeated and alternating taps", taps.testRepeatedAndAlternatingTaps),
    ("Word and punctuation at caret", words.testTrailingWord),
    ("Russian word at caret", words.testRussianWord),
    ("UTF-16 offsets after emoji", words.testUTF16EmojiPrefix),
    ("Joined emoji in word", words.testJoinedEmojiInWord),
    ("Empty fields", words.testEmptyAndWhitespace),
    ("Newline and tab boundaries", words.testNewlineAndTabDoNotReachPreviousWord),
    ("Bounded context offset", words.testBoundedWindowOffset),
    ("Truncated word rejected", words.testTruncatedWordRejected),
    ("Word length limit", words.testOversizedWordRejected),
    ("Trailing space limit", words.testTooManyTrailingSpacesRejected),
    ("Negative offset", words.testNegativeOffsetRejected),
    ("Combining characters", words.testCombiningCharacters),
    ("English and Russian case inversion", transforms.testCaseInversionInBothLanguages),
    ("Preserve symbols and emoji", transforms.testSymbolsAndEmojiArePreserved),
    ("Unicode length changes", transforms.testCaseCanChangeUnicodeLength),
    ("Alphabet detection", transforms.testAlphabetDetection),
    ("Physical mapping and unmapped characters", transforms.testMappingPreservesUnmappedCharactersAndWhitespace),
    ("Tap duration boundaries and backwards clock", boundary.testTapDurationBoundaries),
    ("Wrong modifier release and recovery", boundary.testWrongReleaseAndRecovery),
    ("Duplicate modifier press cancels tap", boundary.testDuplicatePressCancelsTap),
    ("Reset after a cancelled gesture", boundary.testResetAfterCancelledGesture),
    ("Document range overflow", boundary.testDocumentRangeOverflow),
    ("Word limit counts UTF-16 units", boundary.testWordLimitUsesUTF16),
    ("Unicode whitespace boundaries", boundary.testUnicodeWhitespaceBoundaries),
    ("Focus traversal depth limit", boundary.testFocusDepthLimit),
    ("Focus provider priority", boundary.testFocusProviderPriority),
    ("Usable editor with a focus self-cycle", boundary.testUsableFocusSelfCycle),
    ("Complete English and Russian case round trip", boundary.testWholeAlphabetsCaseRoundTrip),
    ("Multiline and empty transformations", boundary.testMultilineAndEmptyTransforms)
]
for (name, run) in cases {
    let before = failures
    run()
    print("\(before == failures ? "PASS" : "FAIL") \(name)")
}
print("\(cases.count) scenarios, \(failures) failed assertions.")
exit(failures == 0 ? 0 : 1)
