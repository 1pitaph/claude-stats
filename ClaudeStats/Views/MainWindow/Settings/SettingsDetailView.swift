import SwiftUI

/// Right-side content for main-window settings mode. The surrounding
/// `MainWindowModeShell` owns the sidebar and `DetailPanel` chrome.
struct SettingsDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let section: SettingsSection
    var onSelectSection: (SettingsSection) -> Void = { _ in }
    @State private var releaseHistoryPresented = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                settingsContent

                if releaseHistoryPresented {
                    ReleaseHistoryPanel(
                        entries: ReleaseHistoryCatalog.entries,
                        onClose: hideReleaseHistory
                    )
                    .frame(width: releaseHistoryPanelWidth(for: proxy.size.width))
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: section) { _, newSection in
            if newSection != .about {
                setReleaseHistoryPresented(false)
            }
        }
    }

    private var settingsContent: some View {
        Group {
            #if !CLAUDE_STATS_LITE
            if activeSection == .notchIsland {
                NotchIslandSettingsView(onSelectSection: onSelectSection)
            } else {
                AppScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        Text(activeSection.title)
                            .font(.sora(28, weight: .semibold))
                            .padding(.bottom, 4)
                        sectionContent
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 52)
                    .padding(.bottom, 28)
                }
            }
            #else
            AppScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(activeSection.title)
                        .font(.sora(28, weight: .semibold))
                        .padding(.bottom, 4)
                    sectionContent
                }
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 52)
                .padding(.bottom, 28)
            }
            #endif
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch activeSection {
        case .general: GeneralSettingsView()
        case .features: FeaturesSettingsView(onSelectSection: onSelectSection)
        case .iCloudSync: CloudStatsSyncSettingsView()
        case .menuBar: MenuBarSettingsView()
        case .notchIsland: EmptyView()
        case .platforms: PlatformsSettingsView()
        case .tracking: TrackingSettingsView(onSelectSection: onSelectSection)
        case .dictionary: DictionarySettingsView()
        case .llm: AppLLMSettingsView()
        case .localAI:
            #if CLAUDE_STATS_LITE
            EmptyView()
            #else
            LocalAIModelsSettingsView()
            #endif
        case .leaderboards: LeaderboardsSettingsView(onSelectSection: onSelectSection)
        case .github: GitHubSettingsView(onSelectSection: onSelectSection)
        case .linuxDo:
            #if CLAUDE_STATS_LITE
            EmptyView()
            #else
            LinuxDoSettingsView(store: env.linuxDo)
            #endif
        case .systemMonitor: SystemMonitorSettingsView(onSelectSection: onSelectSection)
        case .terminal:
            #if CLAUDE_STATS_LITE
            EmptyView()
            #else
            TerminalSettingsView()
            #endif
        case .about: AboutSettingsView(onShowReleaseHistory: showReleaseHistory)
        }
    }

    private var activeSection: SettingsSection {
        SettingsSection.availableCases.contains(section) ? section : .general
    }

    private func showReleaseHistory() {
        setReleaseHistoryPresented(true)
    }

    private func hideReleaseHistory() {
        setReleaseHistoryPresented(false)
    }

    private func setReleaseHistoryPresented(_ isPresented: Bool) {
        guard releaseHistoryPresented != isPresented else { return }
        if reduceMotion {
            releaseHistoryPresented = isPresented
        } else {
            withAnimation(MainWindowMotion.modeSwitchAnimation) {
                releaseHistoryPresented = isPresented
            }
        }
    }

    private func releaseHistoryPanelWidth(for availableWidth: CGFloat) -> CGFloat {
        let available = max(260, availableWidth - 24)
        let target = min(420, max(320, availableWidth * 0.42))
        return min(target, available)
    }
}

#if DEBUG
#Preview("Settings detail") {
    SettingsDetailView(section: .general)
        .environment(AppEnvironment.preview())
        .frame(width: 820, height: 600)
        .background(Color.stxBackground)
}
#endif
