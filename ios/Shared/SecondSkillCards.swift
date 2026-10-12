import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

// Both platforms use the same reviewed collection; original twelve IDs remain stable.
public enum SecondSkillCards {
    public static let all: [StudyCard] = IdiomCatalog.all.map {
        StudyCard(id: $0.id, term: $0.term, meaning: $0.meaning, example: $0.example, note: $0.note, examples: $0.examples)
    }
}
