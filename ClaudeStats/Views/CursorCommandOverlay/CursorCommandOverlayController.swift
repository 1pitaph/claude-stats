import AppKit
import Observation
import QuartzCore
import SwiftUI

@MainActor
final class CursorCommandOverlayController {
    private weak var environment: AppEnvironment?
    private weak var preferences: Preferences?
    private let state = CursorCommandOverlayState()
    private let locator = CursorTextFocusLocator()

    private var panel: NSPanel?
    private var lastTarget: CursorTextFocusTarget?
    private var pollTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var copiedResetTask: Task<Void, Never>?
    private var isStarted = false

    func start(environment: AppEnvironment) {
        guard !isStarted else { return }
        isStarted = true
        self.environment = environment
        self.preferences = environment.preferences
        observePreferences()
        observeScreenChanges()
        observeAppActivation()
        syncWithPreferences()
    }

    func stop() {
        pollTask?.cancel()
        summaryTask?.cancel()
        copiedResetTask?.cancel()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        screenObserver = nil
        activationObserver = nil
        closePanel()
        isStarted = false
    }

    private func observePreferences() {
        guard let preferences else { return }
        withObservationTracking {
            _ = preferences.cursorCommandOverlayEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncWithPreferences()
                self?.observePreferences()
            }
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFocusAndPlacement()
            }
        }
    }

    private func observeAppActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFocusAndPlacement()
            }
        }
    }

    private func syncWithPreferences() {
        guard preferences?.cursorCommandOverlayEnabled == true else {
            pollTask?.cancel()
            pollTask = nil
            closePanel()
            return
        }

        startPollingIfNeeded()
        refreshFocusAndPlacement()
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshFocusAndPlacement()
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    private func refreshFocusAndPlacement() {
        guard preferences?.cursorCommandOverlayEnabled == true else { return }
        guard locator.isTrusted else {
            hidePanel(resetExpanded: true)
            return
        }

        guard let target = locator.locateFocusedTextTarget() else {
            hidePanel(resetExpanded: true)
            return
        }

        lastTarget = target
        ensurePanel()
        applyPanelFrame(animated: false)
        panel?.orderFrontRegardless()
    }

    private func ensurePanel() {
        guard panel == nil, let environment else { return }
        let initialFrame = currentPanelFrame()
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.title = "Cursor Session Commands"

        let rootView = CursorCommandOverlayView(
            state: state,
            onToggleExpanded: { [weak self] in
                self?.toggleExpanded()
            },
            onCollapse: { [weak self] in
                self?.setExpanded(false)
            },
            onCopyCommand: { [weak self] command in
                self?.copyCommand(command)
            }
        )
        .environment(environment)

        let hostingView = CursorCommandOverlayHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        self.panel = panel
    }

    private func closePanel() {
        summaryTask?.cancel()
        copiedResetTask?.cancel()
        panel?.close()
        panel = nil
        state.isExpanded = false
        state.isLoading = false
        state.summaries = []
        state.lastError = nil
        state.copiedCommand = nil
        lastTarget = nil
    }

    private func hidePanel(resetExpanded: Bool) {
        panel?.orderOut(nil)
        lastTarget = nil
        if resetExpanded {
            summaryTask?.cancel()
            state.isExpanded = false
            state.isLoading = false
            state.lastError = nil
        }
    }

    private func toggleExpanded() {
        setExpanded(!state.isExpanded)
    }

    private func setExpanded(_ expanded: Bool) {
        guard state.isExpanded != expanded else { return }
        state.isExpanded = expanded
        if expanded {
            loadSummaries()
        } else {
            summaryTask?.cancel()
            state.isLoading = false
        }
        applyPanelFrame(animated: true)
    }

    private func loadSummaries() {
        guard let environment else { return }
        summaryTask?.cancel()
        state.isLoading = true
        state.lastError = nil
        summaryTask = Task { @MainActor [weak self, store = environment.store] in
            let summaries = await store.recentSessionCommandSummaries(sessionLimit: 5, commandLimit: 3)
            guard let self, !Task.isCancelled else { return }
            self.state.summaries = summaries
            self.state.isLoading = false
            self.applyPanelFrame(animated: true)
        }
    }

    private func copyCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        state.copiedCommand = command
        copiedResetTask?.cancel()
        copiedResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.state.copiedCommand = nil
        }
    }

    private func applyPanelFrame(animated: Bool) {
        guard let panel else { return }
        let frame = currentPanelFrame()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func currentPanelFrame() -> CGRect {
        let targetRect = lastTarget?.rect ?? {
            let mouse = NSEvent.mouseLocation
            return CGRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        }()
        let size = state.isExpanded ? expandedSize : CursorCommandOverlayGeometry.collapsedSize
        return CursorCommandOverlayGeometry.preferredFrame(
            anchorRect: targetRect,
            size: size,
            visibleFrame: CursorCommandOverlayGeometry.bestVisibleFrame(for: targetRect)
        )
    }

    private var expandedSize: CGSize {
        CGSize(
            width: CursorCommandOverlayGeometry.expandedWidth,
            height: expandedHeight
        )
    }

    private var expandedHeight: CGFloat {
        if state.isLoading || state.summaries.isEmpty {
            return CursorCommandOverlayGeometry.minimumExpandedHeight
        }

        let headerHeight: CGFloat = 54
        let bottomPadding: CGFloat = 22
        let sectionsHeight = state.summaries.reduce(CGFloat.zero) { total, summary in
            let commandRows = CGFloat(max(1, summary.commands.count))
            return total + 45 + commandRows * 30 + 12
        }
        let height = headerHeight + sectionsHeight + bottomPadding
        return min(CursorCommandOverlayGeometry.maximumExpandedHeight, max(CursorCommandOverlayGeometry.minimumExpandedHeight, height))
    }
}

private final class CursorCommandOverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
