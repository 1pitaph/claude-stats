import AtollEmbed
import SwiftUI

struct NotchIslandSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    var onSelectSection: (SettingsSection) -> Void = { _ in }
    @SceneStorage("notchIslandSettings.selectedTab") private var selectedTabRaw = NotchIslandSettingsTab.island.rawValue
    @State private var settingsRefreshToken = 0

    private var selectedTab: NotchIslandSettingsTab {
        NotchIslandSettingsTab(rawValue: selectedTabRaw) ?? .island
    }

    var body: some View {
        @Bindable var prefs = env.preferences

        VStack(alignment: .leading, spacing: 0) {
            Text("Notch Island")
                .font(.sora(28, weight: .semibold))
                .padding(.bottom, 18)

            Rectangle()
                .fill(Color.stxStroke)
                .frame(height: 1)

            HStack(spacing: 0) {
                NotchIslandSettingsSidebar(
                    selection: selectedTabBinding,
                    enabledModules: prefs.notchIslandEnabledModules
                )
                .frame(width: 232)
                .frame(maxHeight: .infinity, alignment: .top)

                Rectangle()
                    .fill(Color.stxStroke)
                    .frame(width: 1)

                NotchIslandSettingsDetailPane(
                    tab: selectedTab,
                    preferences: prefs,
                    isFeatureEnabled: prefs.notchIslandEnabled,
                    refreshToken: settingsRefreshToken,
                    onSelectSection: onSelectSection,
                    onSettingChanged: noteSettingChanged
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 52)
        .padding(.bottom, 28)
        .onChange(of: selectedTabRaw) { _, _ in
            noteSettingChanged()
        }
    }

    private var selectedTabBinding: Binding<NotchIslandSettingsTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTabRaw = $0.rawValue }
        )
    }

    private func noteSettingChanged() {
        settingsRefreshToken &+= 1
    }
}

enum NotchIslandSettingsGroup: String, CaseIterable, Identifiable {
    case core
    case live
    case utilities
    case system
    case integrations

    var id: String { rawValue }

    var title: String? {
        switch self {
        case .core: nil
        case .live: "LIVE"
        case .utilities: "UTILITIES"
        case .system: "SYSTEM"
        case .integrations: "INTEGRATIONS"
        }
    }
}

enum NotchIslandSettingsTab: String, CaseIterable, Identifiable {
    case island
    case appearance
    case media
    case stats
    case timer
    case clipboard
    case colorPicker
    case calendar
    case shelf
    case privacy
    case recording
    case focus
    case battery
    case bluetooth
    case downloads
    case osd
    case lockScreenWidgets
    case extensionBridge
    case screenAssistant
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .island: "Island"
        case .appearance: "Appearance"
        case .media: "Media"
        case .stats: "Stats"
        case .timer: "Timer"
        case .clipboard: "Clipboard"
        case .colorPicker: "Color Picker"
        case .calendar: "Calendar"
        case .shelf: "Shelf"
        case .privacy: "Privacy"
        case .recording: "Recording"
        case .focus: "Focus"
        case .battery: "Battery"
        case .bluetooth: "Bluetooth"
        case .downloads: "Downloads"
        case .osd: "OSD"
        case .lockScreenWidgets: "Lock Widgets"
        case .extensionBridge: "Extensions"
        case .screenAssistant: "Screen Assistant"
        case .terminal: "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .island: AppIcon.NotchIsland.island
        case .appearance: AppIcon.NotchIsland.appearance
        case .media: AppIcon.NotchIsland.media
        case .stats: AppIcon.NotchIsland.stats
        case .timer: AppIcon.NotchIsland.timer
        case .clipboard: AppIcon.NotchIsland.clipboard
        case .colorPicker: AppIcon.NotchIsland.colorPicker
        case .calendar: AppIcon.NotchIsland.calendar
        case .shelf: AppIcon.NotchIsland.shelf
        case .privacy: AppIcon.NotchIsland.privacy
        case .recording: AppIcon.NotchIsland.recording
        case .focus: AppIcon.NotchIsland.focus
        case .battery: AppIcon.NotchIsland.battery
        case .bluetooth: AppIcon.NotchIsland.bluetooth
        case .downloads: AppIcon.NotchIsland.downloads
        case .osd: AppIcon.Workspace.configs
        case .lockScreenWidgets: AppIcon.NotchIsland.lockScreenWidgets
        case .extensionBridge: AppIcon.NotchIsland.extensionBridge
        case .screenAssistant: AppIcon.NotchIsland.screenAssistant
        case .terminal: AppIcon.Workspace.terminal
        }
    }

    var group: NotchIslandSettingsGroup {
        switch self {
        case .island, .appearance: .core
        case .media, .stats, .timer, .calendar, .privacy, .recording, .focus, .battery: .live
        case .clipboard, .colorPicker, .shelf, .downloads, .osd, .terminal: .utilities
        case .bluetooth, .lockScreenWidgets: .system
        case .extensionBridge, .screenAssistant: .integrations
        }
    }

    var module: NotchIslandModule? {
        switch self {
        case .island, .appearance:
            nil
        case .media:
            .media
        case .stats:
            .stats
        case .timer:
            .timer
        case .clipboard:
            .clipboard
        case .colorPicker:
            .colorPicker
        case .calendar:
            .calendar
        case .shelf:
            .shelf
        case .privacy:
            .privacy
        case .recording:
            .recording
        case .focus:
            .focus
        case .battery:
            .battery
        case .bluetooth:
            .bluetooth
        case .downloads:
            .downloads
        case .osd:
            .osd
        case .lockScreenWidgets:
            .lockScreenWidgets
        case .extensionBridge:
            .extensionBridge
        case .screenAssistant:
            .screenAssistant
        case .terminal:
            .terminal
        }
    }

    var bridgeTab: AtollSettingsTabID {
        AtollSettingsTabID(rawValue: rawValue) ?? .island
    }

    var subtitle: String {
        if let module {
            return module.settingsDescription
        }
        switch self {
        case .island:
            return "Window placement, sizing, hover behavior, and shortcuts."
        case .appearance:
            return "Visual effects, chrome, media tinting, and idle details."
        default:
            return ""
        }
    }

    static var grouped: [(group: NotchIslandSettingsGroup, tabs: [NotchIslandSettingsTab])] {
        NotchIslandSettingsGroup.allCases.compactMap { group in
            let tabs = allCases.filter { $0.group == group }
            return tabs.isEmpty ? nil : (group, tabs)
        }
    }
}

#if DEBUG
#Preview("Notch Island Settings") {
    NotchIslandSettingsView()
        .environment(AppEnvironment.preview())
        .frame(width: 980, height: 680)
}
#endif
