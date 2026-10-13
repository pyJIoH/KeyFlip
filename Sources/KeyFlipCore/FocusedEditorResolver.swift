/// Resolves the editor from independent focus providers. A web/application shell
/// from one provider must not hide an editable element from another provider.
public enum FocusedEditorResolver {
    public static func resolve<Element>(
        candidates: [Element],
        focusedChild: (Element) -> Element?,
        isUsable: (Element) -> Bool,
        sameElement: (Element, Element) -> Bool,
        maximumDepth: Int = 8
    ) -> Element? {
        for root in candidates {
            var current: Element? = root
            var visited: [Element] = []
            var editor: Element?
            while let element = current, visited.count < maximumDepth {
                guard !visited.contains(where: { sameElement($0, element) }) else { break }
                visited.append(element)
                if isUsable(element) { editor = element }
                current = focusedChild(element)
            }
            if let editor { return editor }
        }
        return nil
    }
}
