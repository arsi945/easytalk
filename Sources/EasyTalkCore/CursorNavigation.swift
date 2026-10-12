import Foundation

/// Finger deltas, independent of host text geometry. Hysteresis prevents a
/// mostly horizontal drag from accidentally jumping between lines.
struct SpaceCursorMotion {
    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var x = 0.0, y = 0.0
    mutating func reset() { axis = .undecided; x = 0; y = 0 }
    mutating func move(dx: Double, dy: Double) -> (columns: Int, rows: Int) {
        guard dx.isFinite, dy.isFinite else { return (0, 0) }
        if axis == .horizontal && dx * x < 0 { x = 0 }
        if axis == .vertical && dy * y < 0 { y = 0 }
        x += dx; y += dy
        switch axis {
        case .undecided:
            if abs(y) >= 20 && abs(y) > abs(x) * 1.4 { axis = .vertical; x = 0 }
            else if abs(x) >= 5 && abs(x) > abs(y) * 0.7 { axis = .horizontal }
        case .horizontal:
            if abs(y) >= 24 && abs(y) > abs(x) * 1.4 { axis = .vertical; x = 0 }
        case .vertical:
            if abs(x) >= 16 && abs(x) > abs(y) * 1.4 { axis = .horizontal; y = 0 }
        }
        if axis == .horizontal {
            let count = Int(x / 10); x -= Double(count) * 10
            if count != 0 { y = 0 }
            return (count, 0)
        }
        if axis == .vertical {
            let count = Int(y / 32); y -= Double(count) * 32
            if count != 0 { x = 0 }
            return (0, count)
        }
        return (0, 0)
    }
}

struct CursorOffset: Equatable {
    var characters: Int
    var utf16: Int
}

/// Layout of the available context only. Host apps do not expose their text geometry
/// to a keyboard, so soft wrapping is estimated; explicit line breaks are exact.
enum CursorNavigation {
    private struct Row { var start: Int; var end: Int; var positions: [Double] }
    static func vertical(before: String, after: String, rows count: Int, width: Double,
                         preferredX: inout Double?, measure: (Character) -> Double) -> CursorOffset {
        let before = String(before.suffix(4000)), after = String(after.prefix(4000))
        let chars = Array(before + after), cursor = before.count
        guard count != 0, !chars.isEmpty else { return CursorOffset(characters: 0, utf16: 0) }
        var rows: [Row] = [], start = 0, positions = [0.0], x = 0.0, index = 0
        let width = max(1, width)
        while index < chars.count {
            let ch = chars[index]
            if ch.isNewline {
                rows.append(Row(start: start, end: index, positions: positions))
                start = index + 1; positions = [0]; x = 0; index += 1; continue
            }
            // Keep a whole word on the next row when it fits there.
            if !ch.isWhitespace && (index == start || chars[index - 1].isWhitespace) {
                var end = index, wordWidth = 0.0
                while end < chars.count && !chars[end].isWhitespace { wordWidth += max(0, measure(chars[end])); end += 1 }
                if index > start && wordWidth <= width && x + wordWidth > width {
                    rows.append(Row(start: start, end: index, positions: positions)); start = index; positions = [0]; x = 0
                }
            }
            let advance = max(0, measure(ch))
            if index > start && x + advance > width {
                rows.append(Row(start: start, end: index, positions: positions)); start = index; positions = [0]; x = 0
            }
            x += advance; positions.append(x); index += 1
        }
        rows.append(Row(start: start, end: chars.count, positions: positions))
        guard let current = rows.lastIndex(where: { cursor >= $0.start && cursor <= $0.end }) else { return CursorOffset(characters: 0, utf16: 0) }
        let currentRow = rows[current]
        if preferredX == nil { preferredX = currentRow.positions[min(cursor - currentRow.start, currentRow.positions.count - 1)] }
        let targetRowIndex = min(rows.count - 1, max(0, current + count))
        guard targetRowIndex != current else { return CursorOffset(characters: 0, utf16: 0) }
        let targetRow = rows[targetRowIndex]
        let targetIndex = targetRow.positions.indices.min { abs(targetRow.positions[$0] - preferredX!) < abs(targetRow.positions[$1] - preferredX!) }!
        let target = targetRow.start + targetIndex
        let fragment = String(chars[min(cursor, target)..<max(cursor, target)])
        return CursorOffset(characters: target - cursor, utf16: fragment.utf16.count * (target < cursor ? -1 : 1))
    }
}
