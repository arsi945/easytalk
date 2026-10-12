import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Вставка в чужое приложение (A7): буфер → ⌘V → восстановление буфера.
/// Без Accessibility результат остаётся в буфере (fallback).
enum Paster {
    enum Outcome { case pasted, copiedOnly }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @discardableResult
    static func insert(_ text: String) -> Outcome {
        let pb = NSPasteboard.general
        guard hasAccessibility else {
            pb.clearContents(); pb.setString(text, forType: .string)
            return .copiedOnly
        }
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        pb.clearContents(); pb.setString(text, forType: .string)
        let mine = pb.changeCount
        sendCommandV()
        // Даём целевому приложению прочитать буфер, затем возвращаем прежнее содержимое.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard pb.changeCount == mine else { return }   // пользователь успел скопировать другое
            pb.clearContents()
            for entry in saved {
                let item = NSPasteboardItem()
                for (t, d) in entry { item.setData(d, forType: t) }
                pb.writeObjects([item])
            }
        }
        return .pasted
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }
}
