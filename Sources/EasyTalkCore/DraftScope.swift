import Foundation

/// A macOS editor owns its whole document, but sends only a selection or current paragraph.
public struct DraftScope: Equatable {
    public let document: String
    public let selection: NSRange
    public let range: NSRange
    public let source: String
    public var isSelection: Bool { selection.length > 0 }
    public init?(document: String, selection: NSRange) {
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= document.utf16.count,
              selection.length <= document.utf16.count - selection.location,
              Self.scalarBoundary(selection.location, in: document),
              Self.scalarBoundary(NSMaxRange(selection), in: document),
              Range(selection, in: document) != nil else { return nil }
        let text = document as NSString
        var range = selection.length > 0 ? selection : text.paragraphRange(for: selection)
        if selection.length == 0 {
            while range.length > 0, [10, 13].contains(Int(text.character(at: NSMaxRange(range) - 1))) { range.length -= 1 }
        }
        // Enter after the final paragraph should not silently disable translation.
        if selection.length == 0 && selection.location == text.length {
            while range.location > 0 && text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                range = text.paragraphRange(for: NSRange(location: range.location - 1, length: 0))
                while range.length > 0, [10, 13].contains(Int(text.character(at: NSMaxRange(range) - 1))) { range.length -= 1 }
            }
        }
        guard let swiftRange = Range(range, in: document) else { return nil }
        let source = String(document[swiftRange])
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.document = document; self.selection = selection; self.range = range; self.source = source
    }
    private static func scalarBoundary(_ offset: Int, in text: String) -> Bool {
        let units = text as NSString
        guard offset > 0, offset < units.length else { return offset == 0 || offset == units.length }
        return !((0xD800...0xDBFF).contains(units.character(at: offset - 1)) && (0xDC00...0xDFFF).contains(units.character(at: offset)))
    }
    public func replacing(with translation: String, current: String, selection currentSelection: NSRange) -> (text: String, cursor: NSRange)? {
        guard current == document, currentSelection == selection, let range = Range(range, in: current) else { return nil }
        return (current.replacingCharacters(in: range, with: translation), NSRange(location: self.range.location + translation.utf16.count, length: 0))
    }
}
