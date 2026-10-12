import AppKit
import ApplicationServices

/// A target is inspected only after the user's explicit Translate action.
/// No global typing capture; field contents are never passed to the AI or logs.
final class DesktopInsertionTarget {
    let app: NSRunningApplication
    private let element: AXUIElement
    private let range: CFRange
    private let valueHash: Int
    private init(app: NSRunningApplication, element: AXUIElement, range: CFRange, valueHash: Int) {
        self.app = app; self.element = element; self.range = range; self.valueHash = valueHash
    }
    static func capture(_ app: NSRunningApplication) -> DesktopInsertionTarget? {
        guard Paster.hasAccessibility, !app.isTerminated,
              let element = focused(app.processIdentifier),
              let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let range = selectedRange(element),
              let value = attribute(element, kAXValueAttribute) as? String,
              value.utf16.count <= 1_000_000 else { return nil }
        var writable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success,
              writable.boolValue else { return nil }
        return .init(app: app, element: element, range: range, valueHash: value.hashValue)
    }
    func stillMatchesFocusedField() -> Bool {
        guard !app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let current = Self.focused(app.processIdentifier), CFEqual(current, element),
              let selection = Self.selectedRange(current), selection.location == range.location, selection.length == range.length,
              let value = Self.attribute(current, kAXValueAttribute) as? String,
              value.hashValue == valueHash else { return false }
        return true
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func focused(_ pid: pid_t) -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range) else { return nil }
        return range
    }
}
