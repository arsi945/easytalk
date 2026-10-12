import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var desktop: DesktopWindowController!
    private var hotkey: Hotkey?
    private var selectionService: DesktopSelectionService?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--desktop-check") {
            guard i + 1 < a.count else { fputs("Usage: --desktop-check OUTPUT_DIRECTORY\n", stderr); exit(2) }
            DesktopQA.run(to: a[i + 1]); NSApp.terminate(nil); return
        }
        desktop = DesktopWindowController()
        selectionService = DesktopSelectionService { [weak self] text in
            guard let self, self.desktop.model.importSelection(text) else { return false }
            self.desktop.show(); return true
        }
        NSApp.servicesProvider = selectionService; NSUpdateDynamicServices()
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "easytalk")
        let menu = NSMenu()
        menu.addItem(withTitle: "Открыть easytalk  ⌃⌥Пробел", action: #selector(openDesktop), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Настройки…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Разрешить вставку в приложения…", action: #selector(askAccessibility), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        hotkey = Hotkey { [weak self] in self?.desktop.show() }
        desktop.show()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { desktop?.show(); return true }
    @objc private func openDesktop() { desktop.show() }
    @objc private func openSettings() { desktop.model.openSettings(); desktop.show() }
    @objc private func askAccessibility() { Paster.requestAccessibility() }
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: "easytalk")
        appMenu.addItem(withTitle: "Настройки…", action: #selector(openSettings), keyEquivalent: ",").target = self
        let services = NSMenu(title: "Службы"); let servicesItem = appMenu.addItem(withTitle: "Службы", action: nil, keyEquivalent: ""); servicesItem.submenu = services; NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть easytalk", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Выйти из easytalk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Скопировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выделить всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
}
