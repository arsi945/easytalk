import Foundation

/// Typing conventions of the system keyboard, as pure functions of the text before the cursor.
public enum TypingRules {
    /// Mirrors UITextAutocapitalizationType without depending on UIKit.
    public enum Capitalization { case none, words, sentences, allCharacters }

    /// Whether the next letter should be uppercase.
    public static func shouldCapitalize(before: String, mode: Capitalization) -> Bool {
        switch mode {
        case .none: return false
        case .allCharacters: return true
        case .words: return before.last.map { $0.isWhitespace } ?? true
        case .sentences:
            guard let last = before.last else { return true }
            if last.isNewline { return true }
            guard last == " " else { return false }
            guard let previous = before.reversed().first(where: { $0 != " " }) else { return true }
            return previous.isNewline || ".!?…".contains(previous)
        }
    }

    /// A second space right after a word turns «word␣» into «word.␣».
    public static func doubleSpaceMakesPeriod(before: String) -> Bool {
        guard before.hasSuffix(" ") else { return false }
        let rest = before.dropLast()
        guard let previous = rest.last else { return false }
        return previous.isLetter || previous.isNumber
    }

    /// Characters removed by one accelerated delete: trailing spaces plus the word before them,
    /// or a single character when the cursor follows punctuation.
    public static func wordDeletionLength(before: String) -> Int {
        let characters = Array(before)
        var index = characters.count
        while index > 0, characters[index - 1] == " " { index -= 1 }
        let spaces = characters.count - index
        var word = 0
        while index > 0, characters[index - 1].isLetter || characters[index - 1].isNumber || characters[index - 1] == "'" || characters[index - 1] == "’" {
            index -= 1; word += 1
        }
        if word == 0 { return characters.isEmpty ? 0 : max(spaces, 1) }
        return spaces + word
    }
}
