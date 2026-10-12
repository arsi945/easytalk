import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DesktopPanelGeometry {
    static func frame(in visible: NSRect, compact: Bool, inputHeight: CGFloat = 64) -> NSRect {
        let width = min(392, max(320, visible.width - 24))
        let height = compact ? min(260 + max(0, inputHeight - 64), visible.height - 24) : min(900, visible.height - 24)
        return NSRect(x: visible.maxX - width - 12, y: visible.maxY - height - 12, width: width, height: height)
    }
}
final class EasyTalkDesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class DesktopWindowController: NSWindowController {
    let model: DesktopModel
    private var destination: NSRunningApplication?
    private var eventMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var activationGeneration = 0
    init(model: DesktopModel = DesktopModel()) {
        self.model = model
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = EasyTalkDesktopPanel(contentRect: DesktopPanelGeometry.frame(in: visible, compact: model.compact), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "easytalk"; window.minSize = NSSize(width: 340, height: model.compact ? 235 : 530); window.isReleasedWhenClosed = false
        window.isFloatingPanel = true; window.hidesOnDeactivate = false; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: DesktopRoot(model: model))
        super.init(window: window)
        model.onCopy = { text in NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        model.onPaste = { [weak self] text in self?.paste(text) }
        model.onPrepareInsertion = { [weak self] in self?.prepareInsertion() }
        model.onCompactChange = { [weak self] _ in self?.placeAtRight(animated: true) }
        model.onInputHeightChange = { [weak self] in self?.placeAtRight(animated: false) }
        model.onImportClipboard = { [weak self] in
            guard let self else { return }
            guard let text = NSPasteboard.general.string(forType: .string) else { self.model.notice = "В буфере нет текста."; return }
            _ = self.model.importSelection(text)
        }
        model.onExport = { [weak self] data in self?.export(data) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.activationGeneration += 1; self.destination = app
            if self.window?.isVisible == true, self.model.page == .compose, !self.model.busy, self.model.canTranslate {
                self.model.insertionDestination = app.localizedName ?? "приложение"
            }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true, self.model.page == .game,
                  !(self.window?.firstResponder is NSTextView), event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            switch event.keyCode {
            case 49: self.model.flipCard(); return nil
            case 123: self.model.moveCard(-1); return nil
            case 124: self.model.moveCard(1); return nil
            default: return event
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
    func show() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { destination = app }
        placeAtRight(animated: false)
        showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func placeAtRight(animated: Bool) {
        guard let window else { return }
        let screen = window.screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        window.minSize = NSSize(width: 340, height: model.compact ? 235 : min(530, screen.visibleFrame.height - 24))
        window.setFrame(DesktopPanelGeometry.frame(in: screen.visibleFrame, compact: model.compact, inputHeight: model.inputHeight), display: true, animate: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    private func paste(_ text: String) {
        guard let target = destination, !target.isTerminated, Paster.hasAccessibility else {
            model.onCopy?(text); model.notice = "Текст скопирован. Перейди в нужное приложение и нажми ⌘V."; return
        }
        let expectedPID = target.processIdentifier
        window?.orderOut(nil); target.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID, !target.isTerminated else {
                self.model.onCopy?(text); self.model.notice = "Приложение не удалось активировать. Текст скопирован для ⌘V."; return
            }
            let result = Paster.insert(text)
            self.model.notice = result == .pasted ? "Текст вставлен в \(target.localizedName ?? "приложение")." : "Текст скопирован для ⌘V."
        }
    }
    private func prepareInsertion() -> ((String) -> Void)? {
        guard let app = destination, !app.isTerminated else { return nil }
        let target = DesktopInsertionTarget.capture(app), generation = activationGeneration
        let accessibility = Paster.hasAccessibility
        return { [weak self] text in
            guard let self else { return }
            func copy(_ message: String) { self.model.onCopy?(text); self.model.notice = message }
            guard accessibility, let target else {
                copy(accessibility ? "Перевод скопирован. Поле не поддерживает безопасную автовставку; нажми ⌘V." : "Перевод скопирован. Разреши вставку в приложения в меню easytalk, затем нажми ⌘V."); return
            }
            guard self.activationGeneration == generation, !app.isTerminated else {
                copy("Цель изменилась. Перевод скопирован для ⌘V."); return
            }
            app.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self else { return }
                guard target.stillMatchesFocusedField() else {
                    self.model.onCopy?(text); self.model.notice = "Поле или курсор изменились. Перевод скопирован для ⌘V."; return
                }
                let result = Paster.insert(text)
                self.model.notice = result == .pasted ? "Перевод отправлен в \(app.localizedName ?? "приложение")." : "Перевод скопирован для ⌘V."
                self.window?.orderFront(nil)
            }
        }
    }
    private func export(_ data: Data) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "easytalk-dictionary.json"; panel.allowedContentTypes = [.json]
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic); self?.model.notice = "Словарь экспортирован." }
            catch { self?.model.notice = "Не удалось сохранить файл: \(error.localizedDescription)" }
        }
    }
}
