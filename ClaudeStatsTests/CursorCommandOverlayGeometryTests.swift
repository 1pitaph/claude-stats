import Foundation
import Testing
@testable import ClaudeStats

@Suite("Cursor command overlay geometry")
struct CursorCommandOverlayGeometryTests {
    @Test("Converts accessibility top-left rect to AppKit bottom-left rect")
    func convertsAccessibilityRect() {
        let axRect = CGRect(x: 100, y: 50, width: 2, height: 20)
        let desktop = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let rect = CursorCommandOverlayGeometry.accessibilityRectToAppKit(axRect, desktopBounds: desktop)

        #expect(rect == CGRect(x: 100, y: 830, width: 2, height: 20))
    }

    @Test("Places overlay to upper right and clamps to visible frame")
    func placesAndClampsFrame() {
        let visible = CGRect(x: 0, y: 0, width: 500, height: 300)
        let anchor = CGRect(x: 480, y: 280, width: 4, height: 16)
        let size = CGSize(width: 120, height: 80)

        let frame = CursorCommandOverlayGeometry.preferredFrame(anchorRect: anchor, size: size, visibleFrame: visible)

        #expect(frame.maxX <= visible.maxX - 6 + 0.001)
        #expect(frame.maxY <= visible.maxY - 6 + 0.001)
        #expect(frame.minX >= visible.minX + 6 - 0.001)
        #expect(frame.minY >= visible.minY + 6 - 0.001)
    }
}
