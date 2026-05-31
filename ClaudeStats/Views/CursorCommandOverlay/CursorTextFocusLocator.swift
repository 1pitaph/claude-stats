import ApplicationServices
import AppKit
import Foundation

struct CursorTextFocusTarget: Sendable, Hashable {
    enum Source: Sendable, Hashable {
        case caret
        case focusedElement
        case mouse
    }

    let rect: CGRect
    let source: Source
}

@MainActor
final class CursorTextFocusLocator {
    private var lastDiagnostic: String?

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestTrustPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func locateFocusedTextTarget() -> CursorTextFocusTarget? {
        guard isTrusted else { return nil }

        let systemElement = AXUIElementCreateSystemWide()
        guard let focusedElement = copyElementAttribute(kAXFocusedUIElementAttribute as CFString, from: systemElement),
              isLikelyTextInput(focusedElement) else {
            return nil
        }

        let screens = CursorCommandOverlayGeometry.liveScreens()
        let desktopBounds = CursorCommandOverlayGeometry.desktopBounds(screens: screens)
        if let caretRect = caretAccessibilityRect(for: focusedElement, desktopBounds: desktopBounds, screens: screens) {
            return CursorTextFocusTarget(rect: caretRect, source: .caret)
        }

        if let elementRect = elementAccessibilityRect(for: focusedElement, desktopBounds: desktopBounds, screens: screens) {
            return CursorTextFocusTarget(rect: elementRect, source: .focusedElement)
        } else if elementAccessibilityRawRect(for: focusedElement) != nil {
            logDiagnosticOnce("focused element frame rejected; falling back to mouse")
        }

        return mouseTarget()
    }

    private func mouseTarget() -> CursorTextFocusTarget {
        let mouse = NSEvent.mouseLocation
        logDiagnosticOnce("using mouse fallback")
        return CursorCommandOverlayGeometry.mouseTarget(at: mouse)
    }

    private func normalizedCaretRect(
        _ axRect: CGRect?,
        label: String,
        desktopBounds: CGRect,
        screens: [CursorCommandOverlayScreen]
    ) -> CGRect? {
        guard let axRect, axRect.isUsableAccessibilityRect else {
            return nil
        }

        let rect = CursorCommandOverlayGeometry.accessibilityRectToAppKit(axRect, desktopBounds: desktopBounds)
        guard let normalized = CursorCommandOverlayGeometry.normalizedCaretRect(rect, screens: screens) else {
            logDiagnosticOnce("\(label) caret bounds rejected")
            return nil
        }
        return normalized
    }

    private func normalizedFocusedElementRect(
        _ axRect: CGRect?,
        desktopBounds: CGRect,
        screens: [CursorCommandOverlayScreen]
    ) -> CGRect? {
        guard let axRect, axRect.isUsableAccessibilityRect else {
            return nil
        }

        let rect = CursorCommandOverlayGeometry.accessibilityRectToAppKit(axRect, desktopBounds: desktopBounds)
        guard let normalized = CursorCommandOverlayGeometry.normalizedFocusedElementRect(rect, screens: screens) else {
            return nil
        }
        return normalized
    }

    private func logDiagnosticOnce(_ message: String) {
        guard lastDiagnostic != message else { return }
        lastDiagnostic = message
        Log.overlay.debug("Cursor overlay locator: \(message, privacy: .public)")
    }

    nonisolated static func caretRangeCandidates(for range: CFRange) -> [CFRange] {
        let location = max(0, range.location)
        let length = max(0, range.length)
        let end = location + length
        var ranges = [CFRange(location: end, length: 0)]
        if length > 0 {
            ranges.append(CFRange(location: location, length: length))
        }
        if end > 0 {
            ranges.append(CFRange(location: end - 1, length: 1))
        }
        return ranges
    }

    private func elementAccessibilityRawRect(for element: AXUIElement) -> CGRect? {
        guard let position = copyCGPointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = copyCGSizeAttribute(kAXSizeAttribute as CFString, from: element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func elementAccessibilityRect(
        for element: AXUIElement,
        desktopBounds: CGRect,
        screens: [CursorCommandOverlayScreen]
    ) -> CGRect? {
        normalizedFocusedElementRect(
            elementAccessibilityRawRect(for: element),
            desktopBounds: desktopBounds,
            screens: screens
        )
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func isLikelyTextInput(_ element: AXUIElement) -> Bool {
        if copyCFRangeAttribute(kAXSelectedTextRangeAttribute as CFString, from: element) != nil {
            return true
        }

        let role = copyStringAttribute(kAXRoleAttribute as CFString, from: element) ?? ""
        let subrole = copyStringAttribute(kAXSubroleAttribute as CFString, from: element) ?? ""
        let roles = Set([role, subrole].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return !roles.isDisjoint(with: Self.textInputRoles)
    }

    private func caretAccessibilityRect(
        for element: AXUIElement,
        desktopBounds: CGRect,
        screens: [CursorCommandOverlayScreen]
    ) -> CGRect? {
        guard let range = copyCFRangeAttribute(kAXSelectedTextRangeAttribute as CFString, from: element) else {
            return nil
        }

        for candidate in Self.caretRangeCandidates(for: range) {
            if let rect = normalizedCaretRect(
                boundsForRange(candidate, in: element),
                label: candidate.length == 0 ? "collapsed" : "selection",
                desktopBounds: desktopBounds,
                screens: screens
            ) {
                return rect
            }
        }
        return nil
    }

    private func boundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var rawValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &rawValue
        ) == .success,
            let rawValue,
            CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }

        let value = rawValue as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(value) == .cgRect,
              AXValueGetValue(value, .cgRect, &rect) else {
            return nil
        }
        return rect
    }

    private func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        copyAttribute(attribute, from: element) as? String
    }

    private func copyCFRangeAttribute(_ attribute: CFString, from element: AXUIElement) -> CFRange? {
        guard let rawValue = copyAttribute(attribute, from: element),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = rawValue as! AXValue
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange,
              AXValueGetValue(value, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func copyCGPointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        guard let rawValue = copyAttribute(attribute, from: element),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = rawValue as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(value) == .cgPoint,
              AXValueGetValue(value, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func copyCGSizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        guard let rawValue = copyAttribute(attribute, from: element),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let value = rawValue as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(value) == .cgSize,
              AXValueGetValue(value, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func copyAttribute(_ attribute: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static let textInputRoles: Set<String> = [
        "AXTextArea",
        "AXTextField",
        "AXComboBox",
        "AXSearchField",
    ]
}

private extension CGRect {
    var isUsableAccessibilityRect: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
            && size.width >= 0
            && size.height > 0
            && !isNull
            && !isInfinite
    }
}
