import AppKit
import Foundation

struct CursorCommandOverlayScreen: Sendable, Hashable {
    let frame: CGRect
    let visibleFrame: CGRect

    init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    @MainActor
    init(screen: NSScreen) {
        self.frame = screen.frame
        self.visibleFrame = screen.visibleFrame
    }
}

enum CursorCommandOverlayGeometry {
    static let collapsedSize = CGSize(width: 38, height: 34)
    static let expandedWidth: CGFloat = 420
    static let minimumExpandedHeight: CGFloat = 178
    static let maximumExpandedHeight: CGFloat = 460

    static func accessibilityRectToAppKit(_ rect: CGRect, desktopBounds: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: desktopBounds.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func preferredFrame(
        anchorRect: CGRect,
        source: CursorTextFocusTarget.Source = .caret,
        size: CGSize,
        visibleFrame: CGRect,
        spacing: CGFloat = 8
    ) -> CGRect {
        let anchor = placementAnchor(for: anchorRect, source: source)
        var origin = CGPoint(x: anchor.x + spacing, y: anchor.y + spacing)
        if origin.x + size.width > visibleFrame.maxX {
            origin.x = anchor.x - size.width - spacing
        }
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = anchor.y - size.height - spacing
        }
        return clamped(CGRect(origin: origin, size: size), to: visibleFrame, margin: 6)
    }

    static func preferredFrame(
        for target: CursorTextFocusTarget,
        size: CGSize,
        screens: [CursorCommandOverlayScreen],
        spacing: CGFloat = 8
    ) -> CGRect {
        preferredFrame(
            anchorRect: target.rect,
            source: target.source,
            size: size,
            visibleFrame: bestVisibleFrame(for: target.rect, screens: screens),
            spacing: spacing
        )
    }

    static func clamped(_ frame: CGRect, to visibleFrame: CGRect, margin: CGFloat = 6) -> CGRect {
        let maxX = max(visibleFrame.minX + margin, visibleFrame.maxX - frame.width - margin)
        let maxY = max(visibleFrame.minY + margin, visibleFrame.maxY - frame.height - margin)
        let x = min(max(frame.minX, visibleFrame.minX + margin), maxX)
        let y = min(max(frame.minY, visibleFrame.minY + margin), maxY)
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }

    @MainActor
    static func liveScreens(_ screens: [NSScreen] = NSScreen.screens) -> [CursorCommandOverlayScreen] {
        screens.map { CursorCommandOverlayScreen(screen: $0) }
    }

    @MainActor
    static func desktopBounds() -> CGRect {
        desktopBounds(screens: liveScreens())
    }

    static func desktopBounds(screens: [CursorCommandOverlayScreen]) -> CGRect {
        screens.map(\.frame).reduce(nil) { partial, frame in
            partial?.union(frame) ?? frame
        } ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    @MainActor
    static func bestVisibleFrame(for rect: CGRect) -> CGRect {
        bestVisibleFrame(for: rect, screens: liveScreens())
    }

    static func bestVisibleFrame(for rect: CGRect, screens: [CursorCommandOverlayScreen]) -> CGRect {
        if let screen = screens.first(where: { $0.visibleFrame.intersects(rect) }) {
            return screen.visibleFrame
        }
        if let screen = screens.first(where: { $0.frame.contains(rect.center) }) {
            return screen.visibleFrame
        }
        if let nearest = screens.min(by: { distance(from: rect.center, to: $0.frame) < distance(from: rect.center, to: $1.frame) }) {
            return nearest.visibleFrame
        }
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    static func normalizedCaretRect(_ rect: CGRect, screens: [CursorCommandOverlayScreen]) -> CGRect? {
        guard rect.hasFiniteMetrics,
              rect.width >= 0,
              rect.height >= 4,
              rect.height <= 180 else {
            return nil
        }

        let normalized = rect.normalizedForCursorOverlay
        guard normalized.width <= 180,
              intersectsKnownScreen(normalized, screens: screens, tolerance: 80) else {
            return nil
        }
        return normalized
    }

    static func normalizedFocusedElementRect(_ rect: CGRect, screens: [CursorCommandOverlayScreen]) -> CGRect? {
        guard rect.hasFiniteMetrics,
              rect.width > 0,
              rect.height > 0,
              let screen = screenIntersecting(rect, screens: screens, tolerance: 40) else {
            return nil
        }

        let visible = screen.visibleFrame
        let visibleArea = max(visible.width * visible.height, 1)
        let areaRatio = (rect.width * rect.height) / visibleArea
        guard rect.height <= min(240, visible.height * 0.35),
              rect.width <= visible.width * 0.97,
              areaRatio <= 0.18,
              !(rect.width >= visible.width * 0.70 && rect.height >= visible.height * 0.18) else {
            return nil
        }
        return rect.normalizedForCursorOverlay
    }

    static func mouseTarget(at point: CGPoint) -> CursorTextFocusTarget {
        CursorTextFocusTarget(
            rect: CGRect(x: point.x, y: point.y, width: 1, height: 1),
            source: .mouse
        )
    }

    private static func placementAnchor(for rect: CGRect, source: CursorTextFocusTarget.Source) -> CGPoint {
        switch source {
        case .caret, .focusedElement, .mouse:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private static func screenIntersecting(
        _ rect: CGRect,
        screens: [CursorCommandOverlayScreen],
        tolerance: CGFloat
    ) -> CursorCommandOverlayScreen? {
        screens.first { screen in
            screen.frame.insetBy(dx: -tolerance, dy: -tolerance).intersects(rect)
                || screen.visibleFrame.insetBy(dx: -tolerance, dy: -tolerance).intersects(rect)
        }
    }

    private static func intersectsKnownScreen(
        _ rect: CGRect,
        screens: [CursorCommandOverlayScreen],
        tolerance: CGFloat
    ) -> Bool {
        screenIntersecting(rect, screens: screens, tolerance: tolerance) != nil
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var hasFiniteMetrics: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
            && size.width >= 0
            && size.height >= 0
            && !isNull
            && !isInfinite
    }

    var normalizedForCursorOverlay: CGRect {
        CGRect(x: minX, y: minY, width: max(2, width), height: max(16, height))
    }
}
