import Defaults
import SwiftUI
import WarpEmbed

@MainActor
final class TerminalManager: ObservableObject {
    static let shared = TerminalManager()

    @Published private(set) var terminalTitle = "Terminal"
    let store = WarpSessionStore()

    private init() {
        store.ensureDefaultSession()
        refreshTitle()
    }

    func restartShell() {
        _ = store.closeSelectedSession(force: true)
        store.ensureDefaultSession()
        refreshTitle()
    }

    func refreshTerminalAppearanceIfNeeded() {
        refreshTitle()
    }

    func focusTerminalIfPossible() {}

    func resignTerminalFirstResponderIfNeeded() {}

    private func refreshTitle() {
        terminalTitle = store.tabs.first(where: { $0.id == store.selectedTabID })?.title ?? "Warp"
    }
}

struct NotchTerminalView: View {
    @ObservedObject var terminalManager = TerminalManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.enableTerminalFeature) var enableTerminalFeature
    @Default(.cornerRadiusScaling) var cornerRadiusScaling
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    private static let terminalClipTopCornerRadius: CGFloat = 6

    private var currentScreenName: String {
        vm.screen ?? DynamicIslandViewCoordinator.shared.selectedScreen
    }

    private var isDynamicIslandMode: Bool {
        shouldUseDynamicIslandMode(for: currentScreenName)
    }

    private var terminalClipShape: UnevenRoundedRectangle {
        let innerBottom = notchTerminalBottomCornerRadii(
            isDynamicIslandMode: isDynamicIslandMode,
            notchState: vm.notchState,
            cornerRadiusScaling: cornerRadiusScaling,
            enableMinimalisticUI: enableMinimalisticUI,
            closedNotchHeight: vm.closedNotchSize.height
        ).innerBottom
        return UnevenRoundedRectangle(
            topLeadingRadius: Self.terminalClipTopCornerRadius,
            bottomLeadingRadius: innerBottom,
            bottomTrailingRadius: innerBottom,
            topTrailingRadius: Self.terminalClipTopCornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if enableTerminalFeature {
                HStack {
                    Image(systemName: "apple.terminal")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))

                    Text(terminalManager.terminalTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        terminalManager.restartShell()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Restart shell")
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal, notchTerminalContentEdgePadding.horizontal)

                WarpHostView(store: terminalManager.store)
                    .clipShape(terminalClipShape)
                    .padding(
                        EdgeInsets(
                            top: notchTerminalContentEdgePadding.top,
                            leading: notchTerminalContentEdgePadding.horizontal,
                            bottom: notchTerminalContentEdgePadding.bottom,
                            trailing: notchTerminalContentEdgePadding.horizontal
                        )
                    )
                    .onHover { hovering in
                        updateSuppression(for: hovering)
                    }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "apple.terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("Terminal is disabled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Enable it in Settings -> Terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear {
            updateSuppression(for: false)
        }
        .onAppear {
            terminalManager.refreshTerminalAppearanceIfNeeded()
            terminalManager.focusTerminalIfPossible()
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}
