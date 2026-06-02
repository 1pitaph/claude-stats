import AppKit
import SwiftUI

struct GanttHorizontalTimelineScrollView<Content: View>: NSViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
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
        context.coordinator.observe(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.viewport = $viewport
        AppScrollbars.configure(scrollView, axes: .horizontal)

        let size = documentSize
        let hostingView = context.coordinator.hostingView ?? NSHostingView(rootView: framedContent())
        hostingView.rootView = framedContent()
        hostingView.frame = CGRect(origin: .zero, size: size)
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
        private var isApplyingOffset = false

        init(viewport: Binding<GanttTimelineViewport>) {
            self.viewport = viewport
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
                guard self.viewport.wrappedValue != next else { return }
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
    }
}
