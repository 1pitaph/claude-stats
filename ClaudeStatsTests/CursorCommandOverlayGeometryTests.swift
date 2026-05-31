import Foundation
import Testing
@testable import ClaudeStats

@Suite("Cursor command overlay geometry")
struct CursorCommandOverlayGeometryTests {
    private let mainScreen = CursorCommandOverlayScreen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 870)
    )

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

    @Test("Large focused element frames are rejected before placement")
    func rejectsLargeFocusedElementFrames() {
        let fullScreenFrame = CGRect(x: 0, y: 0, width: 1440, height: 870)

        let normalized = CursorCommandOverlayGeometry.normalizedFocusedElementRect(
            fullScreenFrame,
            screens: [mainScreen]
        )

        #expect(normalized == nil)
    }

    @Test("Huge anchors do not flip to the lower-left corner")
    func hugeAnchorsDoNotFlipToLowerLeft() {
        let visible = mainScreen.visibleFrame
        let hugeAnchor = CGRect(x: 0, y: 0, width: 1440, height: 870)
        let size = CursorCommandOverlayGeometry.collapsedSize

        let frame = CursorCommandOverlayGeometry.preferredFrame(
            anchorRect: hugeAnchor,
            source: .focusedElement,
            size: size,
            visibleFrame: visible
        )

        #expect(frame.minX > visible.midX)
        #expect(frame.minY > visible.midY)
    }

    @Test("Invalid accessibility rectangles are rejected")
    func rejectsInvalidAccessibilityRects() {
        let screens = [mainScreen]
        let invalids = [
            CGRect.zero,
            CGRect(x: CGFloat.nan, y: 10, width: 2, height: 20),
            CGRect(x: 10, y: CGFloat.infinity, width: 2, height: 20),
            CGRect(x: 10, y: 10, width: -1, height: 20),
            CGRect(x: 10, y: 10, width: 2, height: 400),
            CGRect(x: 10_000, y: 10_000, width: 2, height: 20),
        ]

        for rect in invalids {
            #expect(CursorCommandOverlayGeometry.normalizedCaretRect(rect, screens: screens) == nil)
        }
    }

    @Test("Small focused text fields remain valid")
    func acceptsSmallFocusedTextFields() {
        let field = CGRect(x: 120, y: 640, width: 760, height: 34)

        let normalized = CursorCommandOverlayGeometry.normalizedFocusedElementRect(
            field,
            screens: [mainScreen]
        )

        #expect(normalized == field)
    }

    @Test("Edge placements stay inside visible frame")
    func edgePlacementsStayInsideVisibleFrame() {
        let visible = mainScreen.visibleFrame
        let size = CGSize(width: 120, height: 80)
        let anchors = [
            CGRect(x: visible.minX + 1, y: visible.maxY - 1, width: 1, height: 1),
            CGRect(x: visible.maxX - 1, y: visible.maxY - 1, width: 1, height: 1),
            CGRect(x: visible.maxX - 1, y: visible.minY + 1, width: 1, height: 1),
        ]

        for anchor in anchors {
            let frame = CursorCommandOverlayGeometry.preferredFrame(
                anchorRect: anchor,
                source: .mouse,
                size: size,
                visibleFrame: visible
            )
            #expect(visible.insetBy(dx: 6, dy: 6).contains(frame.origin))
            #expect(frame.maxX <= visible.maxX - 6 + 0.001)
            #expect(frame.maxY <= visible.maxY - 6 + 0.001)
        }
    }

    @Test("Best visible frame handles negative and vertically arranged displays")
    func bestVisibleFrameHandlesMultipleDisplays() {
        let left = CursorCommandOverlayScreen(
            frame: CGRect(x: -1280, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: -1280, y: 0, width: 1280, height: 780)
        )
        let above = CursorCommandOverlayScreen(
            frame: CGRect(x: 0, y: 900, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 900, width: 1440, height: 870)
        )
        let screens = [mainScreen, left, above]

        let topVisible = CursorCommandOverlayGeometry.bestVisibleFrame(
            for: CGRect(x: 100, y: 1200, width: 2, height: 20),
            screens: screens
        )
        let leftVisible = CursorCommandOverlayGeometry.bestVisibleFrame(
            for: CGRect(x: -2000, y: 200, width: 2, height: 20),
            screens: screens
        )

        #expect(topVisible == above.visibleFrame)
        #expect(leftVisible == left.visibleFrame)
    }

    @Test("Caret range candidates prefer collapsed selection end")
    func caretRangeCandidatesPreferCollapsedSelectionEnd() {
        let ranges = CursorTextFocusLocator.caretRangeCandidates(for: CFRange(location: 8, length: 5))

        #expect(ranges.count == 3)
        #expect(ranges[0].location == 13)
        #expect(ranges[0].length == 0)
        #expect(ranges[1].location == 8)
        #expect(ranges[1].length == 5)
        #expect(ranges[2].location == 12)
        #expect(ranges[2].length == 1)
    }
}
