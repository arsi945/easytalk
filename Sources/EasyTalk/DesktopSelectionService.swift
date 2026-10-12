import AppKit

/// Receives a selection supplied by macOS Services. Never reads the global clipboard.
final class DesktopSelectionService: NSObject {
    private let consume: (String) -> Bool
    init(consume: @escaping (String) -> Bool) { self.consume = consume }
    @objc func sendToEasyTalk(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: NSPasteboard.PasteboardType("NSStringPboardType")), consume(text) else {
            error.pointee = "Выдели текст до 2000 символов."; return
        }
    }
}
