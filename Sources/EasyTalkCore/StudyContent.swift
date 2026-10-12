import Foundation

/// Dictionary form is distinct from the inflected meaning in a user's sentence.
public struct LexicalEntry: Codable, Equatable {
    public var headword: String
    public var meanings: [String]
    public var examples: [String]
    public init(headword: String, meanings: [String], examples: [String]) { self.headword = headword; self.meanings = meanings; self.examples = examples }
    public var validated: LexicalEntry? {
        let headword = headword.trimmingCharacters(in: .whitespacesAndNewlines)
        func clean(_ values: [String], maxLength: Int) -> [String] {
            var seen = Set<String>()
            return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.count <= maxLength && seen.insert($0.lowercased()).inserted }
        }
        let meanings = clean(meanings, maxLength: 180), examples = clean(examples, maxLength: 320)
        guard !headword.isEmpty, headword.count <= 100, !meanings.isEmpty, meanings.count <= 4, (2...3).contains(examples.count),
              headword.unicodeScalars.contains(where: { (65...90).contains($0.value) || (97...122).contains($0.value) }),
              examples.allSatisfy({ $0.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) } }) else { return nil }
        return LexicalEntry(headword: headword, meanings: meanings, examples: examples)
    }
    // Reviewed offline correction for the legacy example reported by the author.
    // Original examples; meaning checked against en.wiktionary.org/wiki/successful.
    public static func offline(_ term: String) -> LexicalEntry? {
        if let idiom = IdiomCatalog.all.first(where: { $0.term.caseInsensitiveCompare(term.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) {
            return LexicalEntry(headword: idiom.term, meanings: [idiom.meaning], examples: idiom.examples).validated
        }
        // Base noun/verb senses checked against Cambridge; examples written for easytalk.
        if term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "benefit" {
            return LexicalEntry(headword: "benefit", meanings: ["польза; выгода", "льгота; пособие", "приносить пользу; получать пользу"], examples: ["Regular exercise has many health benefits.", "Students benefit from regular practice.", "The company offers several employee benefits."])
        }
        guard term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "successful" else { return nil }
        return LexicalEntry(headword: "successful", meanings: ["успешный", "удачный; результативный"], examples: ["The meeting was successful.", "She runs a successful business.", "We hope for a successful result."])
    }
}
public struct PhraseVariant: Codable, Equatable {
    public var label: String
    public var text: String
    public var explanation: String
    public init(label: String, text: String, explanation: String) { self.label = label; self.text = text; self.explanation = explanation }
}
public struct RephraseResponse: Codable {
    public var schema_version: Int
    public var variants: [PhraseVariant]
    public init(schema_version: Int = contractSchemaVersion, variants: [PhraseVariant]) { self.schema_version = schema_version; self.variants = variants }
    public func validated(for source: String) -> [PhraseVariant]? {
        guard schema_version == contractSchemaVersion, (2...4).contains(variants.count) else { return nil }
        var seen = Set<String>()
        let valid = variants.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.unicodeScalars.count <= 4000 &&
            !$0.label.isEmpty && $0.label.count <= 50 && !$0.explanation.isEmpty && $0.explanation.count <= 500 &&
            $0.text.caseInsensitiveCompare(source) != .orderedSame && seen.insert($0.text.lowercased()).inserted
        }
        return valid.count >= 2 ? valid : nil
    }
}
