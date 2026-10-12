import Foundation

/// Общие типы ответа AI: тип правки, правка, пол говорящего.
public let contractSchemaVersion = 1

/// Grammatical gender of the first-person speaker; never a rule for other people.
public enum SpeakerGender: String, Codable, CaseIterable {
    case unspecified, male, female
    public var title: String {
        switch self { case .unspecified: return "Не указан"; case .male: return "Мужчина"; case .female: return "Женщина" }
    }
}

public enum DiffType: String, Codable, Equatable {
    case error, unnatural, style
    case unknownWord = "unknown_word"
}

public struct Diff: Codable, Equatable, Identifiable {
    public var id: String
    public var type: DiffType
    public var original: String
    public var corrected: String
    /// Смещения в Unicode code points исходного текста.
    public var start: Int
    public var end: Int

    public init(id: String, type: DiffType, original: String, corrected: String, start: Int, end: Int) {
        self.id = id; self.type = type; self.original = original
        self.corrected = corrected; self.start = start; self.end = end
    }
}
