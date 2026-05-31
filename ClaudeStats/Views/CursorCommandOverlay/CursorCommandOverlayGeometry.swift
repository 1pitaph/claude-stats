import AppKit
import Foundation

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
        size: CGSize,
        visibleFrame: CGRect,
        spacing: CGFloat = 8
    ) -> CGRect {
        var origin = CGPoint(x: anchorRect.maxX + spacing, y: anchorRect.maxY + spacing)
        if origin.x + size.width > visibleFrame.maxX {
            origin.x = anchorRect.minX - size.width - spacing
        }
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = anchorRect.minY - size.height - spacing
        }
        return clamped(CGRect(origin: origin, size: size), to: visibleFrame, margin: 6)
    }

    static func clamped(_ frame: CGRect, to visibleFrame: CGRect, margin: CGFloat = 6) -> CGRect {
        let maxX = max(visibleFrame.minX + margin, visibleFrame.maxX - frame.width - margin)
        let maxY = max(visibleFrame.minY + margin, visibleFrame.maxY - frame.height - margin)
        let x = min(max(frame.minX, visibleFrame.minX + margin), maxX)
        let y = min(max(frame.minY, visibleFrame.minY + margin), maxY)
        return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
    }

    @MainActor
    static func desktopBounds(screens: [NSScreen] = NSScreen.screens) -> CGRect {
        screens.map(\.frame).reduce(nil) { partial, frame in
            partial?.union(frame) ?? frame
        } ?? (NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @MainActor
    static func bestVisibleFrame(for rect: CGRect, screens: [NSScreen] = NSScreen.screens) -> CGRect {
        if let screen = screens.first(where: { $0.visibleFrame.intersects(rect) }) {
            return screen.visibleFrame
        }
        if let screen = screens.first(where: { $0.frame.contains(rect.center) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
