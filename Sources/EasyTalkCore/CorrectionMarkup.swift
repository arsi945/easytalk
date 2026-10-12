import Foundation

public struct CorrectionSpan: Equatable {
    public let text: String
    public let changed: Bool
}

/// Presentation only: keeps the exact source, marking removed/replaced words.
/// Does not alter AI offsets, the saved lesson, or the corrected phrase.
public enum CorrectionMarkup {
    public static func original(_ source: String, corrected: String) -> [CorrectionSpan] {
        guard !source.isEmpty else { return [] }
        guard source != corrected else { return [.init(text: source, changed: false)] }
        let pattern = #"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*|[^\s]"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let original = source as NSString, replacement = corrected as NSString
        let a = regex.matches(in: source, range: NSRange(location: 0, length: original.length))
        let b = regex.matches(in: corrected, range: NSRange(location: 0, length: replacement.length))
        func key(_ value: String) -> String { value.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) }
        let left = a.map { key(original.substring(with: $0.range)) }
        let right = b.map { key(replacement.substring(with: $0.range)) }
        var retained = Set<Int>()
        // A normal lesson is <=2000 scalars. Bound work for old/imported data too.
        if (a.count + 1) * (b.count + 1) <= 4_500_000, min(a.count, b.count) < Int(UInt16.max) {
            let width = b.count + 1
            var table = [UInt16](repeating: 0, count: (a.count + 1) * width)
            for i in a.indices.reversed() {
                for j in b.indices.reversed() {
                    table[i * width + j] = left[i] == right[j] ? 1 + table[(i + 1) * width + j + 1] : max(table[(i + 1) * width + j], table[i * width + j + 1])
                }
            }
            var i = 0, j = 0
            while i < a.count && j < b.count {
                if left[i] == right[j] { retained.insert(i); i += 1; j += 1 }
                else if table[(i + 1) * width + j] >= table[i * width + j + 1] { i += 1 }
                else { j += 1 }
            }
        } else {
            // Conservative bounded fallback: preserve matching prefix/suffix.
            var i = 0
            while i < min(a.count, b.count), left[i] == right[i] { retained.insert(i); i += 1 }
            var x = a.count - 1, y = b.count - 1
            while x >= i && y >= i, left[x] == right[y] { retained.insert(x); x -= 1; y -= 1 }
        }
        var spans = [CorrectionSpan](), cursor = 0
        func append(_ text: String, changed: Bool) {
            guard !text.isEmpty else { return }
            if let last = spans.last, last.changed == changed {
                spans[spans.count - 1] = .init(text: last.text + text, changed: changed)
            } else { spans.append(.init(text: text, changed: changed)) }
        }
        for (i, match) in a.enumerated() {
            append(original.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), changed: false)
            append(original.substring(with: match.range), changed: !retained.contains(i))
            cursor = NSMaxRange(match.range)
        }
        append(original.substring(from: cursor), changed: false)
        return spans
    }
}
