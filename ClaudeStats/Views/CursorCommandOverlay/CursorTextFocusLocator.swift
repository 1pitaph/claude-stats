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

        let desktopBounds = CursorCommandOverlayGeometry.desktopBounds()
        if let caretRect = caretAccessibilityRect(for: focusedElement) {
            let rect = CursorCommandOverlayGeometry.accessibilityRectToAppKit(caretRect, desktopBounds: desktopBounds)
            return CursorTextFocusTarget(rect: rect.normalizedForOverlay, source: .caret)
        }

        if let elementRect = elementAccessibilityRect(for: focusedElement) {
            let rect = CursorCommandOverlayGeometry.accessibilityRectToAppKit(elementRect, desktopBounds: desktopBounds)
            return CursorTextFocusTarget(rect: rect.normalizedForOverlay, source: .focusedElement)
        }

        let mouse = NSEvent.mouseLocation
        return CursorTextFocusTarget(
            rect: CGRect(x: mouse.x, y: mouse.y, width: 1, height: 1),
            source: .mouse
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

    private func caretAccessibilityRect(for element: AXUIElement) -> CGRect? {
        guard let range = copyCFRangeAttribute(kAXSelectedTextRangeAttribute as CFString, from: element) else {
            return nil
        }
        if let rect = boundsForRange(range, in: element), rect.isUsableAccessibilityRect {
            return rect
        }

        guard range.location > 0 else { return nil }
        let previousCharacterRange = CFRange(location: range.location - 1, length: 1)
        return boundsForRange(previousCharacterRange, in: element)
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

    private func elementAccessibilityRect(for element: AXUIElement) -> CGRect? {
        guard let position = copyCGPointAttribute(kAXPositionAttribute as CFString, from: element),
              let size = copyCGSizeAttribute(kAXSizeAttribute as CFString, from: element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
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
    var normalizedForOverlay: CGRect {
        let width = max(2, self.width)
        let height = max(16, self.height)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    var isUsableAccessibilityRect: Bool {
        width.isFinite && height.isFinite && minX.isFinite && minY.isFinite && width >= 0 && height >= 0
    }
}
