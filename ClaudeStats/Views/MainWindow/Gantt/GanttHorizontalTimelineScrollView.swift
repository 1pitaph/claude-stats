import AppKit
import SwiftUI

struct GanttHorizontalTimelineScrollView<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let contentRevisionID: String
    @Binding var viewport: GanttTimelineViewport
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(viewport: $viewport)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.allowsMagnification = false
        scrollView.usesPredominantAxisScrolling = true
        AppScrollbars.configure(scrollView, axes: .horizontal)

        let hostingView = NSHostingView(rootView: framedContent())
        hostingView.frame = CGRect(origin: .zero, size: documentSize)
        scrollView.documentView = hostingView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.hostingView = hostingView
        context.coordinator.markContentRevision(contentRevisionID, documentSize: documentSize)
        context.coordinator.observe(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.viewport = $viewport
        AppScrollbars.configure(scrollView, axes: .horizontal)

        let size = documentSize
        let hostingView = context.coordinator.hostingView ?? NSHostingView(rootView: framedContent())
        context.coordinator.updateHostingViewIfNeeded(
            hostingView,
            documentSize: size,
            contentRevisionID: contentRevisionID
        ) {
            framedContent()
        }
        if scrollView.documentView !== hostingView {
            scrollView.documentView = hostingView
            context.coordinator.hostingView = hostingView
        }

        context.coordinator.applyOffset(viewport.offsetX, in: scrollView)
        context.coordinator.reportViewport(from: scrollView, asynchronously: true)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    private var documentSize: CGSize {
        CGSize(width: max(0, contentWidth), height: max(0, contentHeight))
    }

    private func framedContent() -> AnyView {
        AnyView(content().frame(width: max(0, contentWidth), height: max(0, contentHeight), alignment: .topLeading))
    }

    @MainActor
    final class Coordinator: NSObject {
        var viewport: Binding<GanttTimelineViewport>
        var hostingView: NSHostingView<AnyView>?
        private weak var observedScrollView: NSScrollView?
        private var contentRevisionID: String?
        private var documentSize: CGSize = .zero
        private var isApplyingOffset = false

        init(viewport: Binding<GanttTimelineViewport>) {
            self.viewport = viewport
        }

        func markContentRevision(_ contentRevisionID: String, documentSize: CGSize) {
            self.contentRevisionID = contentRevisionID
            self.documentSize = documentSize
        }

        func updateHostingViewIfNeeded(
            _ hostingView: NSHostingView<AnyView>,
            documentSize: CGSize,
            contentRevisionID: String,
            makeRootView: () -> AnyView
        ) {
            if self.contentRevisionID != contentRevisionID
                || !Self.approximatelyEqual(self.documentSize, documentSize)
            {
                hostingView.rootView = makeRootView()
                self.contentRevisionID = contentRevisionID
            }

            if !Self.approximatelyEqual(hostingView.frame.size, documentSize) {
                hostingView.setFrameSize(documentSize)
            }
            self.documentSize = documentSize
        }

        func observe(_ scrollView: NSScrollView) {
            guard observedScrollView !== scrollView else { return }
            stopObserving()
            observedScrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func stopObserving() {
            if let observedScrollView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: observedScrollView.contentView
                )
            }
            observedScrollView = nil
        }

        func applyOffset(_ offset: CGFloat, in scrollView: NSScrollView) {
            let visibleWidth = scrollView.contentView.bounds.width
            let documentWidth = hostingView?.frame.width ?? scrollView.documentView?.frame.width ?? 0
            let target = GanttTimelineViewport.clampedOffset(
                offset,
                contentWidth: documentWidth,
                viewportWidth: visibleWidth
            )
            let current = scrollView.contentView.bounds.origin.x
            guard abs(current - target) > 0.5 else { return }

            isApplyingOffset = true
            scrollView.contentView.scroll(to: NSPoint(x: target, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingOffset = false
        }

        func reportViewport(from scrollView: NSScrollView, asynchronously: Bool) {
            let update = { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                let documentWidth = self.hostingView?.frame.width ?? scrollView.documentView?.frame.width ?? 0
                let visibleWidth = scrollView.contentView.bounds.width
                let offset = scrollView.contentView.bounds.origin.x
                let next = self.viewport.wrappedValue
                    .withDimensions(contentWidth: documentWidth, viewportWidth: visibleWidth)
                    .withOffset(offset)
                guard self.shouldPublishViewportChange(from: self.viewport.wrappedValue, to: next) else { return }
                self.viewport.wrappedValue = next
            }

            if asynchronously {
                Task { @MainActor in
                    update()
                }
            } else {
                update()
            }
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard let scrollView = observedScrollView else { return }
            reportViewport(from: scrollView, asynchronously: isApplyingOffset)
        }

        private func shouldPublishViewportChange(
            from current: GanttTimelineViewport,
            to next: GanttTimelineViewport
        ) -> Bool {
            guard current != next else { return false }
            guard current.contentWidth > 0, next.contentWidth > 0 else { return true }
            if abs(current.contentWidth - next.contentWidth) > 0.5 { return true }
            if abs(current.offsetX - next.offsetX) > 0.5 { return true }
            if current.isScrollable != next.isScrollable { return true }
            return abs(current.viewportWidth - next.viewportWidth) >= GanttTimelineViewportMetrics.widthStep / 2
        }

        private static func approximatelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
            abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
        }
    }
}
