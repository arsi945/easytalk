import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

public struct Lesson: Codable {
    public var id = UUID()
    public var date = Date()
    public var source: String
    public var response: LearningResponse
    public var unread: Bool
    public var variants: [PhraseVariant]? = nil
    public var dismissedTerms: [String]? = nil
    public var intendedMeaning: String? = nil
}

public struct VocabularyEntry: Codable {
    public var id = UUID()
    public var term: String
    public var meaning: String
    public var kind: String
    public var originalContext: String
    public var correctedContext: String
    public var dictionary: LexicalEntry? = nil
    public var lexical: LexicalEntry? {
        if let profile = dictionary?.validated {
            // Repair the reported legacy inflection without guessing other Russian endings.
            if profile.headword.lowercased() == "benefit", profile.meanings.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "пользу" }) { return LexicalEntry.offline("benefit") }
            return profile
        }
        return LexicalEntry.offline(term)
    }
    public var displayTerm: String { lexical?.headword ?? term }
    public var displayMeaning: String { lexical?.meanings.joined(separator: "; ") ?? meaning }
    public var examples: [String] { lexical?.examples ?? [correctedContext].filter { !$0.isEmpty } }
    public init(id: UUID = UUID(), term: String, meaning: String, kind: String, originalContext: String, correctedContext: String, dictionary: LexicalEntry? = nil) {
        self.id = id; self.term = term; self.meaning = meaning; self.kind = kind
        self.originalContext = originalContext; self.correctedContext = correctedContext; self.dictionary = dictionary?.validated
    }
}

/// Lessons and the personal dictionary. On iOS the defaults are the shared App Group (SharedStorage).
public final class LearningStore {
    /// Imported AI word lists make the dictionary grow faster than single saves did.
    public static let maxWords = 1000
    private let defaults: UserDefaults
    public private(set) var lessons: [Lesson]
    public private(set) var words: [VocabularyEntry]
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lessons = Self.load(Lesson.self, key: "learning.lessons", defaults: defaults)
        lessons = Array(lessons.filter { $0.response.isValid(for: $0.source) }.prefix(1))
        words = Self.load(VocabularyEntry.self, key: "learning.words", defaults: defaults)
        // Keep the current lesson across launches; previous lessons belong to this process session only.
        if let data = try? JSONEncoder().encode(lessons) { defaults.set(data, forKey: "learning.lessons") }
    }
    /// Key prefix of copies kept when stored data could not be read completely.
    public static let unreadableSuffix = ".unreadable."
    /// Reads entry by entry: one unreadable entry does not discard the rest. If anything could not
    /// be read, the original bytes are kept under `<key>.unreadable.<time>` before any later save.
    static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> [T] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let items = try? JSONDecoder().decode([Lossy<T>].self, from: data)
        let values = items?.compactMap(\.value) ?? []
        if items == nil || values.count != items?.count {
            defaults.set(data, forKey: key + unreadableSuffix + String(Int(Date().timeIntervalSince1970)))
        }
        return values
    }
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(T.self) }
    }
    public var unreadCount: Int { lessons.filter { $0.unread }.count }
    public func record(source: String, response: LearningResponse) {
        lessons.insert(Lesson(source: source, response: response, unread: response.hasLearning), at: 0); persist()
    }
    @discardableResult public func revise(_ id: UUID, meaning: String, response: LearningResponse) -> Bool {
        guard let index = lessons.firstIndex(where: { $0.id == id }), meaning.unicodeScalars.count <= 2000,
              !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var valid = response.normalized(for: lessons[index].source) else { return false }
        valid.translated = meaning
        lessons[index].response = valid; lessons[index].intendedMeaning = meaning
        lessons[index].variants = nil; lessons[index].dismissedTerms = nil; lessons[index].unread = false
        lessons[index].date = Date(); persist(); return true
    }
    public func markRead(_ id: UUID) {
        guard let index = lessons.firstIndex(where: { $0.id == id }) else { return }
        lessons[index].unread = false; persist()
    }
    public func contains(_ term: String) -> Bool { words.contains { $0.displayTerm.lowercased() == term.lowercased() || $0.term.lowercased() == term.lowercased() } }
    /// Adding a built-in idiom is an explicit user action, separate from analysis.
    public func saveEntry(_ entry: VocabularyEntry) {
        guard !contains(entry.term), !entry.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        words.insert(entry, at: 0); words = Array(words.prefix(Self.maxWords)); persist()
    }
    public func save(_ suggestion: VocabularySuggestion, lesson: Lesson) {
        guard !contains(suggestion.savedTerm) else { return }
        restoreSuggestion(suggestion.term, lesson: lesson.id)
        words.insert(VocabularyEntry(term: suggestion.savedTerm, meaning: suggestion.dictionary?.validated?.meanings.joined(separator: "; ") ?? suggestion.meaning, kind: suggestion.kind,
            originalContext: lesson.source, correctedContext: lesson.response.corrected, dictionary: suggestion.dictionary), at: 0)
        words = Array(words.prefix(Self.maxWords)); persist()
    }
    public func isDismissed(_ term: String, lesson: Lesson) -> Bool {
        (lesson.dismissedTerms ?? []).contains { $0.lowercased() == term.lowercased() }
    }
    public func dismiss(_ term: String, lesson id: UUID) {
        guard let index = lessons.firstIndex(where: { $0.id == id }), !isDismissed(term, lesson: lessons[index]) else { return }
        lessons[index].dismissedTerms = (lessons[index].dismissedTerms ?? []) + [term]; persist()
    }
    public func restoreSuggestion(_ term: String, lesson id: UUID) {
        guard let index = lessons.firstIndex(where: { $0.id == id }) else { return }
        lessons[index].dismissedTerms = (lessons[index].dismissedTerms ?? []).filter { $0.lowercased() != term.lowercased() }; persist()
    }
    public func setVariants(_ variants: [PhraseVariant], lesson id: UUID) {
        guard let index = lessons.firstIndex(where: { $0.id == id }), let valid = RephraseResponse(variants: variants).validated(for: lessons[index].response.corrected) else { return }
        lessons[index].variants = valid; persist()
    }
    public func setDictionary(_ entry: LexicalEntry, word id: UUID) {
        guard let entry = entry.validated, let index = words.firstIndex(where: { $0.id == id }) else { return }
        words[index].dictionary = entry; persist()
    }
    /// Words from an external AI answer («Вставить слова»). Existing terms are skipped. Returns how many were added.
    @discardableResult public func importWords(_ items: [ImportedWord]) -> Int {
        var added = 0
        // Reversed, so the first word of the list ends up on top.
        for item in items.reversed() where !contains(item.term) {
            words.insert(VocabularyEntry(term: item.term, meaning: item.meaning, kind: item.term.contains(" ") ? "phrase" : "word",
                originalContext: "", correctedContext: item.example), at: 0)
            added += 1
        }
        if added > 0 { words = Array(words.prefix(Self.maxWords)); persist() }
        return added
    }
    /// The app and the keyboard both write the dictionary; re-read before showing or changing it.
    public func reloadWords() { words = Self.load(VocabularyEntry.self, key: "learning.words", defaults: defaults) }
    public func removeWord(_ id: UUID) { words.removeAll { $0.id == id }; persist() }
    public func clearLessons() { lessons.removeAll(); persist() }
    private func persist() {
        // A failed encode must not replace stored data with nothing.
        if let data = try? JSONEncoder().encode(Array(lessons.prefix(1))) { defaults.set(data, forKey: "learning.lessons") }
        if let data = try? JSONEncoder().encode(words) { defaults.set(data, forKey: "learning.words") }
    }
}
