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
        context.coordinator.markContentRevision(contentRevisionID)
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
        AnyView(content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
    }

    @MainActor
    final class Coordinator: NSObject {
        var viewport: Binding<GanttTimelineViewport>
        var hostingView: NSHostingView<AnyView>?
        private weak var observedScrollView: NSScrollView?
        private var contentRevisionID: String?
        private var isReportingViewportAsynchronously = false
        private var isApplyingOffset = false

        init(viewport: Binding<GanttTimelineViewport>) {
            self.viewport = viewport
        }

        func markContentRevision(_ contentRevisionID: String) {
            self.contentRevisionID = contentRevisionID
        }

        func updateHostingViewIfNeeded(
            _ hostingView: NSHostingView<AnyView>,
            documentSize: CGSize,
            contentRevisionID: String,
            makeRootView: () -> AnyView
        ) {
            if self.contentRevisionID != contentRevisionID {
                hostingView.rootView = makeRootView()
                self.contentRevisionID = contentRevisionID
            }

            if !Self.approximatelyEqual(hostingView.frame.size, documentSize) {
                hostingView.frame = CGRect(origin: .zero, size: documentSize)
            }
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
            if asynchronously {
                guard !isReportingViewportAsynchronously else { return }
                isReportingViewportAsynchronously = true
                Task { @MainActor [weak self, weak scrollView] in
                    guard let self else { return }
                    self.isReportingViewportAsynchronously = false
                    guard let scrollView else { return }
                    self.publishViewport(from: scrollView)
                }
            } else {
                publishViewport(from: scrollView)
            }
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard let scrollView = observedScrollView else { return }
            reportViewport(from: scrollView, asynchronously: isApplyingOffset)
        }

        private func publishViewport(from scrollView: NSScrollView) {
            let documentWidth = hostingView?.frame.width ?? scrollView.documentView?.frame.width ?? 0
            let visibleWidth = scrollView.contentView.bounds.width
            let offset = scrollView.contentView.bounds.origin.x
            let next = viewport.wrappedValue
                .withDimensions(contentWidth: documentWidth, viewportWidth: visibleWidth)
                .withOffset(offset)
            guard shouldPublishViewportChange(from: viewport.wrappedValue, to: next) else { return }
            viewport.wrappedValue = next
        }

        private func shouldPublishViewportChange(
            from current: GanttTimelineViewport,
            to next: GanttTimelineViewport
        ) -> Bool {
            GanttTimelineViewportMetrics.shouldPublishViewportChange(from: current, to: next)
        }

        private static func approximatelyEqual(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
            abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
        }
    }
}
