import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

/// One message the user finished in another app. Stored only on this device.
public struct HistoryEntry: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var date: Date
    /// The text that was in the field when it was sent.
    public var text: String
    /// Set when the text came from «Перевести»: what the user wrote and the corrected English.
    public var source: String?
    public var corrected: String?

    public init(id: UUID = UUID(), date: Date, text: String, source: String? = nil, corrected: String? = nil) {
        self.id = id; self.date = date; self.text = text; self.source = source; self.corrected = corrected
    }
}

/// Periods offered for «Скопировать контекст».
public enum HistoryPeriod: String, CaseIterable, Codable {
    case halfHour, hour, today, week, all

    public var title: String {
        switch self {
        case .halfHour: return "30 минут"
        case .hour: return "Час"
        case .today: return "Сегодня"
        case .week: return "Неделя"
        case .all: return "Всё время"
        }
    }

    /// Used in the copied text: «Мои сообщения за сегодня».
    public var phrase: String {
        switch self {
        case .halfHour: return "за последние 30 минут"
        case .hour: return "за последний час"
        case .today: return "за сегодня"
        case .week: return "за неделю"
        case .all: return "за всё время"
        }
    }

    /// The earliest included moment; nil means no lower bound.
    public func start(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .halfHour: return now.addingTimeInterval(-30 * 60)
        case .hour: return now.addingTimeInterval(-60 * 60)
        case .today: return calendar.startOfDay(for: now)
        case .week: return now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .all: return nil
        }
    }
}

/// Automatically collected messages, newest first. Shared by the app and the keyboard (App Group).
public final class InputHistoryStore {
    public static let key = "history.entries"
    public static let retention: TimeInterval = 90 * 24 * 60 * 60
    public static let maxEntries = 3000
    public static let maxLength = 4000
    /// The same text again within this interval is a repeated callback, not a new message.
    public static let duplicateWindow: TimeInterval = 10 * 60

    private let defaults: UserDefaults
    public private(set) var entries: [HistoryEntry]

    public init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        entries = LearningStore.load(HistoryEntry.self, key: Self.key, defaults: defaults).sorted { $0.date > $1.date }
        if prune(now: now) { persist() }
    }

    /// Re-reads entries written by the other process (app or keyboard).
    public func reload(now: Date = Date()) {
        entries = LearningStore.load(HistoryEntry.self, key: Self.key, defaults: defaults).sorted { $0.date > $1.date }
        _ = prune(now: now)
    }

    @discardableResult
    public func add(_ text: String, source: String? = nil, corrected: String? = nil, at date: Date = Date()) -> Bool {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
        guard trimmed.contains(where: { $0.isLetter }) else { return false }
        if let last = entries.first, last.text == trimmed, abs(date.timeIntervalSince(last.date)) < Self.duplicateWindow { return false }
        entries.insert(HistoryEntry(date: date, text: trimmed, source: source, corrected: corrected), at: 0)
        _ = prune(now: date)
        persist()
        return true
    }

    /// Entries of a period, oldest first: the order in which they were written.
    public func entries(in period: HistoryPeriod, now: Date = Date(), calendar: Calendar = .current) -> [HistoryEntry] {
        let start = period.start(now: now, calendar: calendar)
        return entries.filter { entry in start.map { entry.date >= $0 } ?? true }.reversed()
    }

    public func clear() { entries.removeAll(); persist() }

    private func prune(now: Date) -> Bool {
        let kept = Array(entries.filter { now.timeIntervalSince($0.date) <= Self.retention }.prefix(Self.maxEntries))
        let changed = kept.count != entries.count
        entries = kept
        return changed
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}

/// Decides that a message was sent: the field became empty, and not because the user erased it
/// with our delete key. The keyboard cannot see the host app's Send button, so this is the signal.
public struct SentTextDetector {
    private var lastText: String?
    private var lastDocument: UUID?
    private var lastEditWasDeletion = false

    public init() {}

    /// Our delete key was used.
    public mutating func noteDeletion() { lastEditWasDeletion = true }
    /// Our keys inserted text.
    public mutating func noteInsertion() { lastEditWasDeletion = false }

    /// Feed every field change. Returns the text that disappeared when the host cleared the field.
    public mutating func observe(document: UUID?, before: String?, after: String?, selected: String? = nil) -> String? {
        let full = (before ?? "") + (selected ?? "") + (after ?? "")
        let text = full.contains(where: { $0.isLetter }) ? full.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if document != lastDocument {
            // Another field or chat: whatever was there before is a draft, not a sent message.
            lastDocument = document; lastText = text; lastEditWasDeletion = false
            return nil
        }
        if let text {
            // Text that grew without our keys (dictation, paste) is not an erase in progress.
            if text.count > (lastText?.count ?? 0) { lastEditWasDeletion = false }
            lastText = text
            return nil
        }
        guard full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let sent = lastText else { return nil }
        lastText = nil
        defer { lastEditWasDeletion = false }
        return lastEditWasDeletion ? nil : sent
    }
}
