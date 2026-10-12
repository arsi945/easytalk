import Foundation

public struct AnalyzeTranslateRequest: Encodable {
    public var op = "analyze_translate"
    public let schema_version = contractSchemaVersion
    public let native_language = "ru"
    public let target_language = "en"
    public let context = "casual_chat"
    public var text: String
    public var intended_meaning: String?
    public var speaker_gender: SpeakerGender?
    public init(text: String, speakerGender: SpeakerGender = .unspecified, intendedMeaning: String? = nil) {
        self.text = text; self.intended_meaning = intendedMeaning; if intendedMeaning != nil { op = "revise_analysis" }; speaker_gender = speakerGender == .unspecified ? nil : speakerGender
    }
}

public struct LearningDiff: Codable, Equatable {
    public var id: String
    public var type: DiffType
    public var original: String
    public var corrected: String
    public var start: Int
    public var end: Int
    public var explanation: String
    public init(id: String, type: DiffType, original: String, corrected: String, start: Int, end: Int, explanation: String) {
        self.id = id; self.type = type; self.original = original; self.corrected = corrected
        self.start = start; self.end = end; self.explanation = explanation
    }
}

public struct VocabularySuggestion: Codable, Equatable {
    public var term: String
    public var meaning: String
    public var kind: String
    public var dictionary: LexicalEntry?
    public var savedTerm: String { dictionary?.validated?.headword ?? term }
    public init(term: String, meaning: String, kind: String, dictionary: LexicalEntry? = nil) { self.term = term; self.meaning = meaning; self.kind = kind; self.dictionary = dictionary }
}

public struct LearningResponse: Codable, Equatable {
    public var schema_version: Int
    public var corrected: String
    public var translated: String
    public var diffs: [LearningDiff]
    public var vocabulary: [VocabularySuggestion]
    public init(schema_version: Int = contractSchemaVersion, corrected: String, translated: String, diffs: [LearningDiff], vocabulary: [VocabularySuggestion]) {
        self.schema_version = schema_version; self.corrected = corrected; self.translated = translated
        self.diffs = diffs; self.vocabulary = vocabulary
    }
    public var hasLearning: Bool { !diffs.isEmpty || !studyVocabulary.isEmpty }
    public var hasErrors: Bool { diffs.contains { $0.type != .style } }
    /// Unknown native words stay saveable even when AI omits the vocabulary array.
    public var studyVocabulary: [VocabularySuggestion] {
        var words = vocabulary
        for diff in diffs where diff.type == .unknownWord && !diff.corrected.isEmpty {
            guard !words.contains(where: { diff.corrected.range(of: $0.term, options: .caseInsensitive) != nil }) else { continue }
            words.append(VocabularySuggestion(term: diff.corrected, meaning: diff.original,
                kind: diff.corrected.split(whereSeparator: { $0.isWhitespace }).count > 1 ? "phrase" : "word"))
        }
        return words
    }

    /// Locate exact fragments rather than trusting model-provided numeric offsets.
    public func normalized(for source: String) -> LearningResponse? {
        let scalars = Array(source.unicodeScalars)
        guard schema_version == contractSchemaVersion, diffs.count <= 100, vocabulary.count <= 12,
              !corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              corrected.unicodeScalars.count <= 6000, translated.unicodeScalars.count <= 6000 else { return nil }
        var result = self
        var fixed: [LearningDiff] = []
        for var d in diffs {
            let part = Array(d.original.unicodeScalars)
            guard !part.isEmpty, part.count <= scalars.count, d.original != d.corrected,
                  !d.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let hits = (0...(scalars.count - part.count)).filter { start in
                scalars[start..<(start + part.count)].elementsEqual(part)
            }
            guard let start = hits.min(by: { abs(Double($0) - Double(d.start)) < abs(Double($1) - Double(d.start)) }) else { return nil }
            d.start = start; d.end = start + part.count; fixed.append(d)
        }
        fixed.sort { $0.start < $1.start }
        var previousEnd = 0
        for d in fixed {
            guard d.start >= previousEnd else { return nil }
            previousEnd = d.end
        }
        if Self.applying(fixed, to: scalars) != corrected {
            guard let reconciled = Self.reconcile(fixed, source: scalars, target: Array(corrected.unicodeScalars)) else { return nil }
            fixed = reconciled
        }
        for index in fixed.indices { fixed[index].id = "d\(index + 1)" }
        result.diffs = fixed
        // Vocabulary is an optional hint. A canonical form absent from the actual
        // corrected sentence must not reject an otherwise complete translation.
        var seen = Set<String>()
        result.vocabulary = vocabulary.filter {
            let term = $0.term.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["word", "phrase", "idiom"].contains($0.kind) && !term.isEmpty &&
                !$0.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                corrected.range(of: term, options: .caseInsensitive) != nil && seen.insert(term.lowercased()).inserted
        }.map { VocabularySuggestion(term: $0.term.trimmingCharacters(in: .whitespacesAndNewlines), meaning: $0.meaning.trimmingCharacters(in: .whitespacesAndNewlines), kind: $0.kind, dictionary: $0.dictionary?.validated) }
        // Still require exact reconstruction; never drop an invalid correction.
        return result.isValid(for: source) ? result : nil
    }

    private static func applying(_ diffs: [LearningDiff], to source: [Unicode.Scalar]) -> String {
        var output = "", previous = 0
        for d in diffs {
            output += String(String.UnicodeScalarView(source[previous..<d.start])) + d.corrected
            previous = d.end
        }
        return output + String(String.UnicodeScalarView(source[previous...]))
    }

    /// Expand an existing explained edit to include adjacent context omitted by
    /// the model (e.g. became + «всё лучше» → keeps getting better). Each proposed
    /// replacement must occur in the final English text in the same order. No
    /// correction is removed or invented, and the final result is checked exactly.
    private static func reconcile(_ diffs: [LearningDiff], source: [Unicode.Scalar], target: [Unicode.Scalar]) -> [LearningDiff]? {
        // An incomplete style-only proposal must never absorb a grammar change
        // and then incorrectly earn a reward for error-free English.
        guard !diffs.isEmpty, diffs.allSatisfy({ $0.type != .style }) else { return nil }
        var fixed: [LearningDiff] = [], sourceEnd = 0, targetEnd = 0
        for var d in diffs {
            let replacement = Array(d.corrected.unicodeScalars)
            guard !replacement.isEmpty, targetEnd + replacement.count <= target.count else { return nil }
            let gap = Array(source[sourceEnd..<d.start])
            let hits = (targetEnd...(target.count - replacement.count)).filter {
                target[$0..<($0 + replacement.count)].elementsEqual(replacement)
            }
            // Prefer the expected unchanged context when a replacement repeats.
            guard let hit = hits.min(by: { a, b in
                let aGap = Array(target[targetEnd..<a]), bGap = Array(target[targetEnd..<b])
                let ac = commonPrefix(gap, aGap), bc = commonPrefix(gap, bGap)
                return ac == bc ? abs(aGap.count - gap.count) < abs(bGap.count - gap.count) : ac > bc
            }) else { return nil }
            let targetGap = Array(target[targetEnd..<hit])
            var prefix = commonPrefix(gap, targetGap)
            while prefix > 0 && prefix < gap.count && isWord(gap[prefix - 1]) && isWord(gap[prefix]) { prefix -= 1 }
            let originalEnd = d.end
            d.start = sourceEnd + prefix
            d.original = String(String.UnicodeScalarView(source[d.start..<d.end]))
            d.corrected = String(String.UnicodeScalarView(targetGap[prefix...])) + d.corrected
            fixed.append(d); sourceEnd = originalEnd; targetEnd = hit + replacement.count
        }
        let sourceGap = Array(source[sourceEnd...]), targetGap = Array(target[targetEnd...])
        if sourceGap != targetGap {
            var suffix = 0
            while suffix < min(sourceGap.count, targetGap.count) && sourceGap[sourceGap.count - suffix - 1] == targetGap[targetGap.count - suffix - 1] { suffix += 1 }
            while suffix > 0 && suffix < sourceGap.count && isWord(sourceGap[sourceGap.count - suffix - 1]) && isWord(sourceGap[sourceGap.count - suffix]) { suffix -= 1 }
            let last = fixed.count - 1
            fixed[last].end = source.count - suffix
            fixed[last].original = String(String.UnicodeScalarView(source[fixed[last].start..<fixed[last].end]))
            fixed[last].corrected += String(String.UnicodeScalarView(targetGap[..<(targetGap.count - suffix)]))
        }
        return applying(fixed, to: source) == String(String.UnicodeScalarView(target)) ? fixed : nil
    }
    private static func commonPrefix(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        var count = 0
        while count < min(a.count, b.count) && a[count] == b[count] { count += 1 }
        return count
    }
    private static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar)
    }

    /// Never congratulate the user on an incomplete or inconsistent model response.
    public func isValid(for source: String) -> Bool {
        guard schema_version == contractSchemaVersion,
              !corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              translated.unicodeScalars.count <= 6000, corrected.unicodeScalars.count <= 6000,
              diffs.count <= 100, vocabulary.count <= 12 else { return false }
        let scalars = Array(source.unicodeScalars)
        var previous = 0, output = "", ids = Set<String>()
        for d in diffs {
            guard d.start >= previous, d.end > d.start, d.end <= scalars.count,
                  !d.id.isEmpty, ids.insert(d.id).inserted, d.original != d.corrected,
                  String(String.UnicodeScalarView(scalars[d.start..<d.end])) == d.original,
                  !d.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            output += String(String.UnicodeScalarView(scalars[previous..<d.start])) + d.corrected
            previous = d.end
        }
        output += String(String.UnicodeScalarView(scalars[previous...]))
        guard output == corrected else { return false }
        return vocabulary.allSatisfy {
            ["word", "phrase", "idiom"].contains($0.kind) && !$0.term.isEmpty && !$0.meaning.isEmpty &&
            corrected.range(of: $0.term, options: .caseInsensitive) != nil
        }
    }
}

/// Immutable snapshot of the accessible field. No cursor movement is needed to replace it.
struct InputSnapshot: Equatable {
    var document: UUID?
    var before: String?
    var after: String?
    var selected: String?

    /// Current paragraph: the selection, or the line around the cursor (text on both sides of it).
    var source: String? {
        guard document != nil else { return nil }
        if let selected, !selected.isEmpty { return selected }
        guard before != nil || after != nil else { return nil }
        return leadingLine + trailingLine
    }
    private var leadingLine: String {
        String(before?.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).last ?? "")
    }
    private var trailingLine: String {
        String(after?.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).first ?? "")
    }
    /// Characters of the paragraph after the cursor.
    var trailingCount: Int { isSelection ? 0 : trailingLine.count }
    /// The same text in UTF-16 units: what adjustTextPosition(byCharacterOffset:) moves by, as in cursor
    /// navigation. Counting characters stops short of the paragraph end after an emoji or accent.
    var trailingUTF16: Int { isSelection ? 0 : trailingLine.utf16.count }
    var isSelection: Bool { selected?.isEmpty == false }
    var canReplace: Bool { source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
}
