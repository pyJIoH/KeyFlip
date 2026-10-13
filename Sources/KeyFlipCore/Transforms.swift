import Foundation

public enum Action: Equatable { case layout, invertCase }
public enum Alphabet: Equatable { case english, russian, mixed, neither }

public enum Transforms {
    public static func invertCase(_ text: String) -> String {
        text.map { character in
            let value = String(character)
            return character.isUppercase ? value.lowercased()
                : character.isLowercase ? value.uppercased() : value
        }.joined()
    }

    public static func alphabet(of text: String) -> Alphabet {
        let latin = text.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
        let cyrillic = text.unicodeScalars.contains { (0x400...0x4FF).contains($0.value) }
        switch (latin, cyrillic) {
        case (true, true): return .mixed
        case (true, false): return .english
        case (false, true): return .russian
        case (false, false): return .neither
        }
    }

    public static func convert(_ text: String, using mapping: [String: String]) -> String {
        text.map { mapping[String($0)] ?? String($0) }.joined()
    }
}
