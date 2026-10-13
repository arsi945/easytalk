import Foundation

/// One word offered in the suggestion row. Suggestions are only offered: nothing is replaced automatically,
/// so the user's own mistakes stay in the text and in the history for the AI review.
public struct WordSuggestion: Equatable {
    public enum Kind: Equatable {
        /// The user's iOS text replacement (Settings → Keyboard → Text Replacement).
        case replacement
        /// A word the user often writes in sent messages.
        case history
        /// The spell checker's fix for a misspelled word.
        case correction
        /// The spell checker's completion of a started word.
        case completion
    }
    public var text: String
    public var kind: Kind
    public init(text: String, kind: Kind) { self.text = text; self.kind = kind }
}

/// A word from the user's own messages: how it is usually written and how often.
public struct KnownWord: Equatable {
    public var text: String
    public var count: Int
}

/// Pure ranking logic; the keyboard supplies the system spell checker's answers.
public enum WordSuggestions {
    public static let limit = 3

    /// The word right before the cursor: letters and digits, with apostrophes and hyphens inside.
    public static func currentWord(before: String) -> String {
        var characters: [Character] = []
        for character in before.reversed() {
            guard character.isLetter || character.isNumber || character == "'" || character == "’" || character == "-" else { break }
            characters.append(character)
        }
        var word = String(characters.reversed())
        while let first = word.first, first == "'" || first == "’" || first == "-" { word.removeFirst() }
        return word
    }

    /// The spell checker language: by the word's script, else by the keyboard layout.
    public static func language(of word: String, russianLayout: Bool) -> String {
        if word.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) { return "ru_RU" }
        if word.unicodeScalars.contains(where: { $0.isASCII && $0.properties.isAlphabetic }) { return "en_US" }
        return russianLayout ? "ru_RU" : "en_US"
    }

    /// Words of the user's sent messages, keyed in lowercase. A word ever written in lowercase is shown in
    /// lowercase; names that are always capitalized keep their capital.
    public static func vocabulary(from texts: [String], minLength: Int = 2, maxWords: Int = 3000) -> [String: KnownWord] {
        var words: [String: KnownWord] = [:]
        for text in texts {
            text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, _, _, _ in
                guard let word = substring, word.count >= minLength, word.contains(where: { $0.isLetter }) else { return }
                let key = word.lowercased()
                var known = words[key] ?? KnownWord(text: word, count: 0)
                known.count += 1
                if word == key { known.text = key }
                words[key] = known
            }
        }
        guard words.count > maxWords else { return words }
        return Dictionary(uniqueKeysWithValues: words.sorted { $0.value.count > $1.value.count }.prefix(maxWords).map { ($0.key, $0.value) })
    }

    /// Up to three suggestions, best first: a text replacement for exactly this shortcut, fixes when the word
    /// is misspelled (unless the user often writes it), the user's own words with this beginning, then the
    /// spell checker's completions. The typed word itself is never offered back.
    public static func suggest(for word: String, replacements: [String: String], vocabulary: [String: KnownWord],
                               isMisspelled: Bool, guesses: [String], completions: [String]) -> [WordSuggestion] {
        guard !word.isEmpty else { return [] }
        let key = word.lowercased()
        var result: [WordSuggestion] = []
        var seen: Set<String> = [key]
        func add(_ text: String, _ kind: WordSuggestion.Kind, matchingCase: Bool = true) {
            let value = matchingCase ? matchCase(text, to: word) : text
            guard result.count < limit, !value.isEmpty, seen.insert(value.lowercased()).inserted else { return }
            result.append(WordSuggestion(text: value, kind: kind))
        }
        if let replacement = replacements[key] { add(replacement, .replacement, matchingCase: false) }
        if isMisspelled && vocabulary[key] == nil { guesses.forEach { add($0, .correction) } }
        let own = vocabulary.values.filter { $0.text.lowercased().hasPrefix(key) && $0.text.lowercased() != key }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.text < $1.text }
        own.prefix(limit).forEach { add($0.text, .history) }
        completions.forEach { add($0, .completion) }
        return result
    }

    /// «hel» → «hello», «Hel» → «Hello», «HEL» → «HELLO»; a capital in the suggestion itself (a name) is kept.
    static func matchCase(_ text: String, to typed: String) -> String {
        if typed.count > 1 && typed == typed.uppercased() && typed != typed.lowercased() { return text.uppercased() }
        if let first = typed.first, first.isUppercase { return text.prefix(1).uppercased() + text.dropFirst() }
        return text
    }
}
