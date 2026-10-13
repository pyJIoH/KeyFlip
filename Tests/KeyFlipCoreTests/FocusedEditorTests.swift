import KeyFlipCore

struct FocusedEditorTests {
    private func resolve(_ roots: [Int], children: [Int: Int] = [:], editable: Set<Int>) -> Int? {
        FocusedEditorResolver.resolve(candidates: roots, focusedChild: { children[$0] },
                                     isUsable: { editable.contains($0) }, sameElement: ==)
    }

    func testShellDoesNotHideSystemEditor() {
        expectEqual(resolve([1, 2], editable: [2]), 2)
    }
    func testDeepestFocusedEditorWins() {
        expectEqual(resolve([1, 9], children: [1: 2, 2: 3], editable: [2, 3, 9]), 3)
    }
    func testCyclesDoNotHideOtherProviders() {
        expectEqual(resolve([1, 9], children: [1: 2, 2: 1], editable: [9]), 9)
    }
    func testRejectsUnfocusedAndUnreadableElements() {
        expectNil(resolve([1, 2], editable: [9]))
        expectNil(resolve([], editable: [9]))
    }
}
