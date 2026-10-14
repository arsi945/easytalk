import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

public struct StudyCard: Equatable {
    public var id: String
    public var term: String
    public var meaning: String
    public var example: String
    public var note: String
    public var personal: Bool = false
    public var examples: [String]
    public var lexical: Bool
    public init(id: String, term: String, meaning: String, example: String, note: String, personal: Bool = false, examples: [String]? = nil, lexical: Bool = true) {
        self.id = id; self.term = term; self.meaning = meaning; self.example = example; self.note = note; self.personal = personal
        self.examples = examples ?? [example].filter { !$0.isEmpty }; self.lexical = lexical
    }
}

public enum VocabularyFilter: Int, CaseIterable {
    case all, inGame, learned
    public var title: String { switch self { case .all: return "Все"; case .inGame: return "В игре"; case .learned: return "Выучил" } }
}

/// Explicit "Запомнил" is independent of saving a word to the dictionary.
public final class StudyProgressStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var learnedIDs: Set<String> { Set(defaults.stringArray(forKey: "practice.learned") ?? []) }
    public var sessions: Int { max(0, defaults.integer(forKey: "practice.sessions")) }
    public func isLearned(_ id: String) -> Bool { learnedIDs.contains(id) }
    public func setLearned(_ id: String, _ value: Bool) {
        var ids = learnedIDs
        // An explicitly learned built-in idiom stays visible after returning to play.
        if id.hasPrefix("second-skill."), value || ids.contains(id) {
            var introduced = Set(defaults.stringArray(forKey: "practice.introduced") ?? [])
            introduced.insert(id); defaults.set(Array(introduced).sorted(), forKey: "practice.introduced")
        }
        if value { ids.insert(id) } else { ids.remove(id) }
        defaults.set(Array(ids).sorted(), forKey: "practice.learned")
    }
    public func finishSession() { defaults.set(sessions + 1, forKey: "practice.sessions") }
    public func pool(words: [VocabularyEntry]) -> [StudyCard] {
        let personal = words.map { StudyCard(id: "word." + $0.id.uuidString, term: $0.displayTerm,
            meaning: $0.displayMeaning, example: $0.examples.first ?? "", note: $0.lexical == nil ? "Перевод из твоей фразы. Словарное значение можно уточнить." : "Словарная форма", personal: true, examples: $0.examples, lexical: $0.lexical != nil) }
        let terms = Set(personal.map { $0.term.lowercased() })
        return personal + SecondSkillCards.all.filter { !terms.contains($0.term.lowercased()) }
    }
    public func dictionaryCards(words: [VocabularyEntry], filter: VocabularyFilter = .all) -> [StudyCard] {
        let introduced = Set(defaults.stringArray(forKey: "practice.introduced") ?? []).union(learnedIDs)
        return pool(words: words).filter { $0.personal || introduced.contains($0.id) }.filter {
            switch filter { case .all: return true; case .inGame: return !isLearned($0.id); case .learned: return isLearned($0.id) }
        }
    }
    public func candidates(words: [VocabularyEntry], reviewLearned: Bool = false) -> [StudyCard] {
        // A word saved without a translation has no back side yet.
        let translated = pool(words: words).filter { !$0.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let all = translated.filter { reviewLearned || !isLearned($0.id) }
        // Personal words first. Each session contains distinct cards, never an endless feed.
        return all.filter { $0.personal }.shuffled() + all.filter { !$0.personal }.shuffled()
    }
}

/// A two-sided flashcard session. Seeing the translation never implies mastery.
public final class StudySession {
    public private(set) var cards: [StudyCard]
    public let initialCount: Int
    public private(set) var index = 0
    public private(set) var showingBack = false
    private var rememberedIDs = Set<String>()
    public var rememberedCount: Int { rememberedIDs.count }
    public var current: StudyCard? { cards.indices.contains(index) ? cards[index] : nil }
    public var finished: Bool { current == nil }
    public init(candidates: [StudyCard], limit: Int = 4) {
        var seen = Set<String>()
        cards = Array(candidates.filter { seen.insert($0.term.lowercased()).inserted }.prefix(max(0, limit)))
        initialCount = cards.count
    }
    public func refresh(from pool: [StudyCard]) { cards = cards.map { card in pool.first { $0.id == card.id } ?? card } }
    @discardableResult public func flip() -> Bool {
        guard current != nil else { return false }; showingBack.toggle(); return true
    }
    /// Explicit mastery removes the card from this round, not from the dictionary.
    @discardableResult public func archiveCurrent() -> StudyCard? {
        guard showingBack, let current else { return nil }
        rememberedIDs.insert(current.id); cards.remove(at: index); showingBack = false
        return current
    }
    @discardableResult public func advance(remembered: Bool = false) -> Bool {
        guard current != nil, showingBack else { return false }
        if remembered { _ = setRemembered(true) }
        return move(by: 1)
    }
    /// Paging never implies mastery, and works from either face or back from the end.
    @discardableResult public func move(by direction: Int) -> Bool {
        guard !cards.isEmpty, direction == -1 || direction == 1 else { return false }
        let next = index + direction
        guard next >= 0, next <= cards.count, next != index else { return false }
        index = next; showingBack = false; return true
    }
    @discardableResult public func setRemembered(_ remembered: Bool) -> Bool {
        guard showingBack, let current else { return false }
        if remembered { rememberedIDs.insert(current.id) } else { rememberedIDs.remove(current.id) }
        return true
    }
}

/// Counts only verified, successfully applied analysis of English input.
public final class RewardProgress {
    public static let phrases = ["Молодчина!", "Прекрасно!", "Так держать!", "Чистая работа!", "Отличный английский!"]
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var successes: Int { max(0, defaults.integer(forKey: "rewards.successes")) }
    public func record(source: String, hasErrors: Bool) -> String? {
        guard source.unicodeScalars.contains(where: { (65...90).contains(Int($0.value)) || (97...122).contains(Int($0.value)) }), !hasErrors else { return nil }
        let count = successes; defaults.set(count + 1, forKey: "rewards.successes")
        return Self.phrases[count % Self.phrases.count]
    }
}
