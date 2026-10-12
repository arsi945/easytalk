import Foundation
#if canImport(EasyTalkCore)
import EasyTalkCore
#endif

/// «Скопировать контекст»: the prompt plus the messages of a period, ready to paste into any AI chat.
public enum ContextExport {
    /// Large chats accept much more, but a shorter context keeps the answer focused.
    public static let maxCharacters = 60_000

    /// `prompt` replaces the default task from prompts/context_export.md (used by tests).
    public static func text(entries: [HistoryEntry], period: HistoryPeriod, prompt: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU"); formatter.dateFormat = "dd.MM HH:mm"
        let lines = entries.map { entry -> String in
            var line = "[\(formatter.string(from: entry.date))] \(entry.text)"
            if let source = entry.source, let corrected = entry.corrected {
                line += "\n   Написал сам: «\(source)». Правильно по-английски: «\(corrected)»."
            }
            return line
        }
        // When everything does not fit, the newest messages are kept.
        var kept: [String] = [], size = 0
        for line in lines.reversed() {
            guard size + line.count + 1 <= maxCharacters else { break }
            kept.insert(line, at: 0); size += line.count + 1
        }
        let omitted = lines.count - kept.count
        var header = "Мои сообщения \(period.phrase): \(kept.count)"
        if omitted > 0 { header += " (ещё \(omitted) более старых не поместились)" }
        let numbered = kept.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let task = (prompt ?? contextExportPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
        return [task, header, numbered].joined(separator: "\n\n") + "\n"
    }
}

public struct ImportedWord: Equatable {
    public var term: String
    public var meaning: String
    public var example: String
    public init(term: String, meaning: String, example: String = "") { self.term = term; self.meaning = meaning; self.example = example }
}

/// «Вставить слова»: reads the word block that the context prompt asks the AI to print at the end.
public enum WordImport {
    public static let startMarker = "EASYTALK-WORDS", endMarker = "END-EASYTALK-WORDS"
    public static let maxWords = 50

    /// Tolerates what chats add around the block: code fences, bullets, bold, table pipes.
    public static func parse(_ text: String) -> [ImportedWord] {
        let lines = text.components(separatedBy: .newlines).map(clean)
        // The last block wins: an answer may quote the format before the real list.
        guard let start = lines.lastIndex(of: startMarker) else { return [] }
        var words: [ImportedWord] = [], seen = Set<String>()
        for line in lines[(start + 1)...] {
            if line == endMarker { break }
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, parts[0].contains(where: { $0.isLetter }), !parts[1].isEmpty,
                  parts[0].count <= 80, parts[1].count <= 200,
                  !parts[0].lowercased().hasPrefix("английское") else { continue }
            guard seen.insert(parts[0].lowercased()).inserted else { continue }
            let example = parts.count > 2 ? String(parts[2...].joined(separator: " | ").prefix(300)) : ""
            words.append(ImportedWord(term: parts[0], meaning: parts[1], example: example))
            if words.count == maxWords { break }
        }
        return words
    }

    private static func clean(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespaces)
        for bullet in ["- ", "* ", "• "] where line.hasPrefix(bullet) { line.removeFirst(bullet.count) }
        line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }
        return line.trimmingCharacters(in: .whitespaces)
    }
}
