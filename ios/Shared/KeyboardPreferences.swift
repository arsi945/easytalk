import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

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
}
