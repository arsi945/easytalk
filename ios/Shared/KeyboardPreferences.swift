import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

/// A short hint about the keyboard, shown once in the status line when the keyboard appears.
public struct KeyboardTip: Equatable {
    public let id: String
    public let text: String
}

public enum KeyboardTips {
    /// In the order they are shown. IDs are stored; do not change them.
    public static let all: [KeyboardTip] = [
        KeyboardTip(id: "translate-message",
                    text: "«Перевести» переводит всё сообщение. Выдели часть — переведётся только она. Что переводить — в ⚙."),
        KeyboardTip(id: "suggestions",
                    text: "Подсказки слов над клавишами выключены. Включить — ⚙ → «Подсказки слов»."),
        KeyboardTip(id: "add-word",
                    text: "Выдели слово или фразу и нажми «В словарь» — оно попадёт в твой словарь."),
        KeyboardTip(id: "cursor",
                    text: "Удерживай пробел и веди палец — курсор двигается по тексту."),
        KeyboardTip(id: "context",
                    text: "📋 копирует твои сообщения с заданием для любого ИИ. Вставь в чат и получи разбор ошибок."),
        KeyboardTip(id: "alternates",
                    text: "Удерживай «ь», чтобы ввести «ъ», и «е» — чтобы ввести «ё»."),
        KeyboardTip(id: "space-shift",
                    text: "Двойной пробел ставит точку. Двойное нажатие ⇧ включает Caps Lock."),
    ]
    /// Tips are spaced out so the keyboard does not lecture on every appearance.
    public static let interval: TimeInterval = 30 * 60
}

/// Keyboard settings live in the extension, alongside its learning data.
public final class KeyboardPreferences {
    public static let availableSymbols = Array(".,?!—+=@#:;-'\"()/_&*%[]{}").map(String.init)
    public static let defaultSymbols = Array(".,?!—+=@#").map(String.init)
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var hasSpeakerGender: Bool { defaults.object(forKey: "keyboard.speakerGender") != nil }
    public var speakerGender: SpeakerGender {
        get { SpeakerGender(rawValue: defaults.string(forKey: "keyboard.speakerGender") ?? "") ?? .unspecified }
        set { defaults.set(newValue.rawValue, forKey: "keyboard.speakerGender") }
    }
    public var rewardsEnabled: Bool {
        get { defaults.object(forKey: "keyboard.rewards") == nil ? true : defaults.bool(forKey: "keyboard.rewards") }
        set { defaults.set(newValue, forKey: "keyboard.rewards") }
    }
    public var secondSkillEnabled: Bool {
        get { defaults.object(forKey: "keyboard.secondSkill") == nil ? true : defaults.bool(forKey: "keyboard.secondSkill") }
        set { defaults.set(newValue, forKey: "keyboard.secondSkill") }
    }
    /// Automatic history of sent messages for «Скопировать контекст». On by default.
    public var historyEnabled: Bool {
        get { defaults.object(forKey: "keyboard.history") == nil ? true : defaults.bool(forKey: "keyboard.history") }
        set { defaults.set(newValue, forKey: "keyboard.history") }
    }
    /// Last period chosen for «Скопировать контекст»; shared by the app and the keyboard.
    public var contextPeriod: HistoryPeriod {
        get { HistoryPeriod(rawValue: defaults.string(forKey: "keyboard.contextPeriod") ?? "") ?? .today }
        set { defaults.set(newValue.rawValue, forKey: "keyboard.contextPeriod") }
    }
    /// The last chosen layout survives keyboard restarts.
    public var russianLayout: Bool {
        get { defaults.bool(forKey: "keyboard.russian") }
        set { defaults.set(newValue, forKey: "keyboard.russian") }
    }
    /// The word suggestion row above the letters. Off by default: it takes room; a keyboard tip tells it exists.
    public var suggestionsEnabled: Bool {
        get { defaults.bool(forKey: "keyboard.suggestions") }
        set { defaults.set(newValue, forKey: "keyboard.suggestions") }
    }
    /// What «Перевести» takes without a selection. The whole message by default: that is what people send.
    public var translateScope: TranslateScope {
        get { TranslateScope(rawValue: defaults.string(forKey: "keyboard.translateScope") ?? "") ?? .message }
        set { defaults.set(newValue.rawValue, forKey: "keyboard.translateScope") }
    }
    /// Light vibration on every key press (needs Full Access). On by default.
    public var hapticsEnabled: Bool {
        get { defaults.object(forKey: "keyboard.haptics") == nil ? true : defaults.bool(forKey: "keyboard.haptics") }
        set { defaults.set(newValue, forKey: "keyboard.haptics") }
    }
    public var symbolRowEnabled: Bool {
        get { defaults.object(forKey: "keyboard.symbolRow") == nil ? true : defaults.bool(forKey: "keyboard.symbolRow") }
        set { defaults.set(newValue, forKey: "keyboard.symbolRow") }
    }
    public var symbols: [String] {
        get {
            guard let saved = defaults.stringArray(forKey: "keyboard.symbols") else { return Self.defaultSymbols }
            var seen = Set<String>()
            return Array(saved.filter { Self.availableSymbols.contains($0) && seen.insert($0).inserted }.prefix(12))
        }
        set { defaults.set(newValue, forKey: "keyboard.symbols") }
    }
    @discardableResult public func toggle(_ symbol: String) -> Bool {
        guard Self.availableSymbols.contains(symbol) else { return false }
        var selected = symbols
        if selected.contains(symbol) { selected.removeAll { $0 == symbol } }
        else { guard selected.count < 12 else { return false }; selected.append(symbol) }
        symbols = selected; return true
    }
    public func resetSymbols() { symbols = Self.defaultSymbols }

    /// Set by the keyboard each time it opens with Full Access, so the app can tell the keyboard is ready.
    public var fullAccessSeen: Date? {
        get { defaults.object(forKey: "keyboard.fullAccessSeen") as? Date }
        set { defaults.set(newValue, forKey: "keyboard.fullAccessSeen") }
    }
    /// One tip at a time when the keyboard appears. On by default.
    public var tipsEnabled: Bool {
        get { defaults.object(forKey: "keyboard.tips") == nil ? true : defaults.bool(forKey: "keyboard.tips") }
        set { defaults.set(newValue, forKey: "keyboard.tips") }
    }
    public var shownTips: Set<String> {
        get { Set(defaults.stringArray(forKey: "keyboard.shownTips") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "keyboard.shownTips") }
    }
    /// The next unseen tip, marked as shown. Nil when tips are off, one was shown recently, or all were shown.
    /// The suggestions tip is skipped once the row is already on.
    public func takeTip(now: Date = Date()) -> KeyboardTip? {
        guard tipsEnabled else { return nil }
        if let last = defaults.object(forKey: "keyboard.lastTip") as? Date, now.timeIntervalSince(last) < KeyboardTips.interval {
            return nil
        }
        var shown = shownTips
        if suggestionsEnabled { shown.insert("suggestions") }
        guard let tip = KeyboardTips.all.first(where: { !shown.contains($0.id) }) else { return nil }
        shown.insert(tip.id)
        shownTips = shown
        defaults.set(now, forKey: "keyboard.lastTip")
        return tip
    }
    /// «Показать советы снова»: from the first tip, on the next appearance.
    public func resetTips() {
        shownTips = []
        defaults.removeObject(forKey: "keyboard.lastTip")
        tipsEnabled = true
    }
}
