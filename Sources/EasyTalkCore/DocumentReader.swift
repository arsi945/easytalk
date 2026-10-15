import Foundation

/// iOS shows a keyboard only part of the field around the caret; in some apps (Telegram) it stops at a
/// sentence or even a comma. To translate a whole message the keyboard walks the caret to the end of the
/// field, then back to its start, collecting the text piece by piece, and returns the caret where it was.
/// This type decides each step; the keyboard moves the caret, waits and reports what the proxy shows.
public struct DocumentReader {
    public enum Step: Equatable {
        /// Move the caret by this many UTF-16 units, wait, then read again.
        case move(Int)
        /// The proxy has not caught up with the last move yet: wait and read again.
        case wait
        /// The whole field around the original caret. Move by `restore` to put the caret back.
        case done(before: String, after: String, restore: Int)
        /// Too long or the proxy stopped responding. Move by `restore` and use what the proxy shows.
        case failed(restore: Int)
    }

    public static let maxSteps = 200
    /// UTF-16 units; a translation takes up to 2000 characters anyway.
    public static let maxLength = 12_000
    public static let maxWaits = 6

    private var collectingBackward = false
    /// UTF-16 units moved towards the end and towards the start.
    private var forward = 0
    private var backward = 0
    /// The text after the original caret, and the whole field collected from its end.
    private var afterText = ""
    private var collected = ""
    private var steps = 0
    private var waits = 0
    /// What the proxy showed before the last move; the same view again means it has not updated yet.
    private var viewBeforeMove: [String?]?

    public init() {}

    private var restore: Int { backward - forward }

    public mutating func read(before: String?, after: String?) -> Step {
        steps += 1
        guard steps <= Self.maxSteps else { return .failed(restore: restore) }
        if let previous = viewBeforeMove, previous == [before, after] {
            waits += 1
            return waits > Self.maxWaits ? .failed(restore: restore) : .wait
        }
        waits = 0
        if !collectingBackward {
            let tail = after ?? ""
            if !tail.isEmpty {
                afterText += tail
                forward += tail.utf16.count
                guard forward <= Self.maxLength else { return .failed(restore: restore) }
                viewBeforeMove = [before, after]
                return .move(tail.utf16.count)
            }
            // At the end of the field: from here, collect towards the start.
            collectingBackward = true
        }
        let head = before ?? ""
        guard !head.isEmpty else { return finish() }
        collected = head + collected
        backward += head.utf16.count
        guard collected.utf16.count <= Self.maxLength else { return .failed(restore: restore) }
        viewBeforeMove = [before, after]
        return .move(-head.utf16.count)
    }

    private func finish() -> Step {
        let fieldLength = collected.utf16.count
        let afterLength = afterText.utf16.count
        guard collected.hasSuffix(afterText), afterLength <= fieldLength else { return .failed(restore: restore) }
        let split = collected.utf16.index(collected.utf16.startIndex, offsetBy: fieldLength - afterLength)
        guard let index = split.samePosition(in: collected) else { return .failed(restore: restore) }
        return .done(before: String(collected[..<index]), after: afterText, restore: restore)
    }

    /// After the caret is back, what the proxy shows must be the edges of the collected text around it.
    /// Otherwise the caret did not return exactly and replacing would delete the wrong text.
    public static func matches(before: String, after: String, visibleBefore: String?, visibleAfter: String?) -> Bool {
        before.hasSuffix(visibleBefore ?? "") && after.hasPrefix(visibleAfter ?? "")
    }
}
