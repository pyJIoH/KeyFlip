import AppKit
import Carbon
import KeyFlipCore

struct KeyboardLayout: Identifiable {
    let id: String
    let name: String
    let source: TISInputSource
    let language: String

    func characters(key: UInt16, shifted: Bool) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var output = [UniChar](repeating: 0, count: 16)
        let result = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), shifted ? UInt32(shiftKey >> 8) : 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                    &deadKey, output.count, &length, &output)
        guard result == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: output, count: length)
        guard text.count == 1, !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return text
    }
}

final class Layouts {
    private(set) var available: [KeyboardLayout] = []
    var englishID: String {
        get { UserDefaults.standard.string(forKey: "englishLayout") ?? "com.apple.keylayout.US" }
        set { UserDefaults.standard.set(newValue, forKey: "englishLayout") }
    }
    var russianID: String {
        get { UserDefaults.standard.string(forKey: "russianLayout") ?? "com.apple.keylayout.Russian" }
        set { UserDefaults.standard.set(newValue, forKey: "russianLayout") }
    }

    init() { reload() }
    func reload() {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        available = sources.compactMap { source in
            func property(_ key: CFString) -> AnyObject? {
                guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
                return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
            }
            guard let id = property(kTISPropertyInputSourceID) as? String,
                  let name = property(kTISPropertyLocalizedName) as? String,
                  property(kTISPropertyInputSourceIsEnabled) as? Bool == true,
                  property(kTISPropertyInputSourceIsSelectCapable) as? Bool == true,
                  TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil else { return nil }
            let languages = property(kTISPropertyInputSourceLanguages) as? [String] ?? []
            let isUS = id == "com.apple.keylayout.US" || id == "com.apple.keylayout.ABC"
            guard isUS || languages.contains("ru") else { return nil }
            return KeyboardLayout(id: id, name: name, source: source, language: isUS ? "en" : "ru")
        }
        if !available.contains(where: { $0.id == englishID }), let first = available.first(where: { $0.language == "en" }) { englishID = first.id }
        if !available.contains(where: { $0.id == russianID }), let first = available.first(where: { $0.language == "ru" }) { russianID = first.id }
    }

    var currentID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    func conversion(for text: String) throws -> (text: String, target: KeyboardLayout) {
        guard let english = available.first(where: { $0.id == englishID }),
              let russian = available.first(where: { $0.id == russianID }) else {
            throw AppFailure.message("Enable U.S. (or ABC) and Russian in macOS Keyboard settings, then refresh layouts.")
        }
        let from: KeyboardLayout
        let to: KeyboardLayout
        switch Transforms.alphabet(of: text) {
        case .english: (from, to) = (english, russian)
        case .russian: (from, to) = (russian, english)
        case .mixed: throw AppFailure.message("Select text in one language to convert its layout.")
        case .neither:
            guard currentID == english.id || currentID == russian.id else {
                throw AppFailure.message("Choose the English or Russian input source first.")
            }
            (from, to) = currentID == russian.id ? (russian, english) : (english, russian)
        }
        var mapping: [String: String] = [:]
        // Printable main keyboard positions only; omit keypad duplicates and control keys.
        for key in UInt16(0)...UInt16(50) {
            for shifted in [false, true] {
                if let source = from.characters(key: key, shifted: shifted),
                   let target = to.characters(key: key, shifted: shifted), mapping[source] == nil {
                    mapping[source] = target
                }
            }
        }
        return (Transforms.convert(text, using: mapping), to)
    }

    func select(_ layout: KeyboardLayout) throws {
        guard TISSelectInputSource(layout.source) == noErr, currentID == layout.id else {
            throw AppFailure.message("Text converted, but macOS could not switch the keyboard layout.")
        }
    }

    func toggle() throws {
        let targetID = currentID == russianID ? englishID : russianID
        guard let target = available.first(where: { $0.id == targetID }) else {
            throw AppFailure.message("Enable U.S. and Russian in Keyboard settings, then refresh layouts.")
        }
        try select(target)
    }
}

enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
