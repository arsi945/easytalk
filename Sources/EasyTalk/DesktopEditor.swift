import AppKit
import SwiftUI

/// Uses the same TextKit wrapping, font and insets as the editable NSTextView.
enum DesktopEditorMetrics {
    static let minimumHeight: CGFloat = 64
    static func height(for text: String, width: CGFloat, maximum: CGFloat) -> CGFloat {
        let storage = NSTextStorage(string: text.isEmpty || text.hasSuffix("\n") ? text + " " : text,
                                    attributes: [.font: NSFont.systemFont(ofSize: 20)])
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(20, width - 36), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 5
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return min(maximum, max(minimumHeight, ceil(layout.usedRect(for: container).height + 36)))
    }
}

struct DesktopGrowingEditor: View {
    @ObservedObject var model: DesktopModel
    @State private var width: CGFloat = 360
    private var height: CGFloat { DesktopEditorMetrics.height(for: model.draft, width: width, maximum: model.compact ? 184 : 320) }
    var body: some View {
        DesktopEditor(model: model).frame(height: height)
            .overlay(alignment: .topLeading) {
                if model.draft.isEmpty {
                    Text("Напиши по-английски…").font(.system(size: 20)).foregroundColor(.secondary)
                        .padding(.leading, 23).padding(.top, 18).allowsHitTesting(false)
                }
            }
            .background(GeometryReader { geometry in
                Color.clear.onAppear { width = geometry.size.width }
                    .onChange(of: geometry.size.width) { width = $0 }
            })
            .onAppear { model.updateInputHeight(height) }
            .onChange(of: height) { model.updateInputHeight($0) }
    }
}

/// Native editing/selection/undo, rather than a second keyboard on macOS.
struct DesktopEditor: NSViewRepresentable {
    @ObservedObject var model: DesktopModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 64)); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        let text = DesktopTextView(frame: scroll.contentView.bounds)
        text.minSize = NSSize(width: 0, height: 28); text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.delegate = context.coordinator; text.isRichText = false; text.allowsUndo = true
        text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.font = .systemFont(ofSize: 20); text.textColor = .labelColor; text.drawsBackground = false
        text.textContainerInset = NSSize(width: 18, height: 18)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        text.translate = { model.translate() }; text.cancelAnalysis = { if model.busy { model.translate() } }
        text.setAccessibilityLabel("Текст для перевода")
        scroll.documentView = text; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.model = model
        context.coordinator.applying = true
        defer { context.coordinator.applying = false }
        if text.string != model.draft {
            text.insertText(model.draft, replacementRange: NSRange(location: 0, length: text.string.utf16.count))
            text.undoManager?.setActionName("Перевод")
        }
        if text.selectedRange() != model.selection { text.setSelectedRange(model.selection) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var model: DesktopModel; var applying = false
        init(_ model: DesktopModel) { self.model = model }
        func textDidChange(_ notification: Notification) { update(notification) }
        func textViewDidChangeSelection(_ notification: Notification) { update(notification) }
        private func update(_ notification: Notification) {
            guard !applying, let text = notification.object as? NSTextView else { return }
            model.edit(text.string, selection: text.selectedRange())
        }
    }
}
final class DesktopTextView: NSTextView {
    var translate: (() -> Void)?; var cancelAnalysis: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command { translate?(); return }
        if event.keyCode == 53 { cancelAnalysis?(); return }
        super.keyDown(with: event)
    }
}
