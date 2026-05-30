import SwiftUI

enum MainWindowMode: String, Sendable {
    case app
    case linuxDo
    case sessions
    case configs
    case memory
    case chat
    case settings
    case network
    case warp
    case ops
}

enum MainWindowMotion {
    static let appSidebarWidth: CGFloat = 240
    static let linuxDoSidebarWidth: CGFloat = 240
    static let sessionsSidebarWidth: CGFloat = 240
    static let configsSidebarWidth: CGFloat = 240
    static let memorySidebarWidth: CGFloat = 240
    static let chatSidebarWidth: CGFloat = 240
    static let settingsSidebarWidth: CGFloat = 220
    static let networkSidebarWidth: CGFloat = 240
    static let warpSidebarWidth: CGFloat = 240
    static let opsSidebarWidth: CGFloat = 240

    private static let detailOffset: CGFloat = 10

    static var modeSwitchAnimation: Animation {
        .timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.28)
    }

    static var appDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: -detailOffset).combined(with: .opacity),
            removal: .offset(x: -detailOffset).combined(with: .opacity)
        )
    }

    static var appSidebarTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    static var secondarySidebarTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    static var linuxDoDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var sessionsDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var settingsDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var configsDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var memoryDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var chatDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var networkDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var warpDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }

    static var opsDetailTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(x: detailOffset).combined(with: .opacity),
            removal: .offset(x: detailOffset).combined(with: .opacity)
        )
    }
}

/// Stable two-column shell for the main window. The sidebar column transitions
/// directly between app, LinuxDo, sessions, configs, memory, settings, network, Warp, and ops
/// navigation while the detail panel stays mounted so its leading boundary can
/// move with the sidebar width.
struct MainWindowModeShell<AppSidebar: View, LinuxDoSidebar: View, SessionsSidebar: View, ConfigsSidebar: View, MemorySidebar: View, ChatSidebar: View, SettingsSidebar: View, NetworkSidebar: View, WarpSidebar: View, OpsSidebar: View, AppDetail: View, LinuxDoDetail: View, SessionsDetail: View, ConfigsDetail: View, MemoryDetail: View, ChatDetail: View, SettingsDetail: View, NetworkDetail: View, WarpDetail: View, OpsDetail: View>: View {
    let mode: MainWindowMode
    let sidebarVisible: Bool
    let boundaryFalloffEnabled: Bool

    private let appSidebar: AppSidebar
    private let linuxDoSidebar: LinuxDoSidebar
    private let sessionsSidebar: SessionsSidebar
    private let configsSidebar: ConfigsSidebar
    private let memorySidebar: MemorySidebar
    private let chatSidebar: ChatSidebar
    private let settingsSidebar: SettingsSidebar
    private let networkSidebar: NetworkSidebar
    private let warpSidebar: WarpSidebar
    private let opsSidebar: OpsSidebar
    private let appDetail: AppDetail
    private let linuxDoDetail: LinuxDoDetail
    private let sessionsDetail: SessionsDetail
    private let configsDetail: ConfigsDetail
    private let memoryDetail: MemoryDetail
    private let chatDetail: ChatDetail
    private let settingsDetail: SettingsDetail
    private let networkDetail: NetworkDetail
    private let warpDetail: WarpDetail
    private let opsDetail: OpsDetail

    init(
        mode: MainWindowMode,
        sidebarVisible: Bool,
        boundaryFalloffEnabled: Bool,
        @ViewBuilder appSidebar: () -> AppSidebar,
        @ViewBuilder linuxDoSidebar: () -> LinuxDoSidebar,
        @ViewBuilder sessionsSidebar: () -> SessionsSidebar,
        @ViewBuilder configsSidebar: () -> ConfigsSidebar,
        @ViewBuilder memorySidebar: () -> MemorySidebar,
        @ViewBuilder chatSidebar: () -> ChatSidebar,
        @ViewBuilder settingsSidebar: () -> SettingsSidebar,
        @ViewBuilder networkSidebar: () -> NetworkSidebar,
        @ViewBuilder warpSidebar: () -> WarpSidebar,
        @ViewBuilder opsSidebar: () -> OpsSidebar,
        @ViewBuilder appDetail: () -> AppDetail,
        @ViewBuilder linuxDoDetail: () -> LinuxDoDetail,
        @ViewBuilder sessionsDetail: () -> SessionsDetail,
        @ViewBuilder configsDetail: () -> ConfigsDetail,
        @ViewBuilder memoryDetail: () -> MemoryDetail,
        @ViewBuilder chatDetail: () -> ChatDetail,
        @ViewBuilder settingsDetail: () -> SettingsDetail,
        @ViewBuilder networkDetail: () -> NetworkDetail,
        @ViewBuilder warpDetail: () -> WarpDetail,
        @ViewBuilder opsDetail: () -> OpsDetail
    ) {
        self.mode = mode
        self.sidebarVisible = sidebarVisible
        self.boundaryFalloffEnabled = boundaryFalloffEnabled
        self.appSidebar = appSidebar()
        self.linuxDoSidebar = linuxDoSidebar()
        self.sessionsSidebar = sessionsSidebar()
        self.configsSidebar = configsSidebar()
        self.memorySidebar = memorySidebar()
        self.chatSidebar = chatSidebar()
        self.settingsSidebar = settingsSidebar()
        self.networkSidebar = networkSidebar()
        self.warpSidebar = warpSidebar()
        self.opsSidebar = opsSidebar()
        self.appDetail = appDetail()
        self.linuxDoDetail = linuxDoDetail()
        self.sessionsDetail = sessionsDetail()
        self.configsDetail = configsDetail()
        self.memoryDetail = memoryDetail()
        self.chatDetail = chatDetail()
        self.settingsDetail = settingsDetail()
        self.networkDetail = networkDetail()
        self.warpDetail = warpDetail()
        self.opsDetail = opsDetail()
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarDeck
                .frame(width: sidebarWidth, alignment: .leading)
                .clipped()

            DetailPanel(
                roundedLeading: detailRoundedLeading,
                boundaryFalloffEnabled: boundaryFalloffEnabled
            ) {
                detailContent
            }
        }
    }

    private var sidebarWidth: CGFloat {
        switch mode {
        case .app:
            sidebarVisible ? MainWindowMotion.appSidebarWidth : 0
        case .linuxDo:
            sidebarVisible ? MainWindowMotion.linuxDoSidebarWidth : 0
        case .sessions:
            sidebarVisible ? MainWindowMotion.sessionsSidebarWidth : 0
        case .configs:
            sidebarVisible ? MainWindowMotion.configsSidebarWidth : 0
        case .memory:
            sidebarVisible ? MainWindowMotion.memorySidebarWidth : 0
        case .chat:
            sidebarVisible ? MainWindowMotion.chatSidebarWidth : 0
        case .settings:
            MainWindowMotion.settingsSidebarWidth
        case .network:
            sidebarVisible ? MainWindowMotion.networkSidebarWidth : 0
        case .warp:
            sidebarVisible ? MainWindowMotion.warpSidebarWidth : 0
        case .ops:
            sidebarVisible ? MainWindowMotion.opsSidebarWidth : 0
        }
    }

    private var detailRoundedLeading: Bool {
        switch mode {
        case .app:
            return sidebarVisible
        case .linuxDo:
            return sidebarVisible
        case .sessions:
            return sidebarVisible
        case .configs:
            return sidebarVisible
        case .memory:
            return sidebarVisible
        case .chat:
            return sidebarVisible
        case .settings:
            return true
        case .network:
            return sidebarVisible
        case .warp:
            return sidebarVisible
        case .ops:
            return sidebarVisible
        }
    }

    private var appSidebarIsActive: Bool {
        mode == .app && sidebarVisible
    }

    private var linuxDoSidebarIsActive: Bool {
        mode == .linuxDo && sidebarVisible
    }

    private var sessionsSidebarIsActive: Bool {
        mode == .sessions && sidebarVisible
    }

    private var configsSidebarIsActive: Bool {
        mode == .configs && sidebarVisible
    }

    private var memorySidebarIsActive: Bool {
        mode == .memory && sidebarVisible
    }

    private var chatSidebarIsActive: Bool {
        mode == .chat && sidebarVisible
    }

    private var settingsSidebarIsActive: Bool {
        mode == .settings
    }

    private var networkSidebarIsActive: Bool {
        mode == .network && sidebarVisible
    }

    private var warpSidebarIsActive: Bool {
        mode == .warp && sidebarVisible
    }

    private var opsSidebarIsActive: Bool {
        mode == .ops && sidebarVisible
    }

    private var sidebarDeck: some View {
        ZStack(alignment: .leading) {
            switch mode {
            case .app:
                appSidebar
                    .frame(width: MainWindowMotion.appSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(appSidebarIsActive)
                    .accessibilityHidden(!appSidebarIsActive)
                    .transition(MainWindowMotion.appSidebarTransition)
            case .linuxDo:
                linuxDoSidebar
                    .frame(width: MainWindowMotion.linuxDoSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(linuxDoSidebarIsActive)
                    .accessibilityHidden(!linuxDoSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            case .sessions:
                sessionsSidebar
                    .frame(width: MainWindowMotion.sessionsSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(sessionsSidebarIsActive)
                    .accessibilityHidden(!sessionsSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            case .configs:
                configsSidebar
                    .frame(width: MainWindowMotion.configsSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(configsSidebarIsActive)
                    .accessibilityHidden(!configsSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            case .memory:
                memorySidebar
                    .frame(width: MainWindowMotion.memorySidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(memorySidebarIsActive)
                    .accessibilityHidden(!memorySidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            case .chat:
                chatSidebar
                    .frame(width: MainWindowMotion.chatSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(chatSidebarIsActive)
                    .accessibilityHidden(!chatSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            case .settings:
                settingsSidebar
                    .frame(width: MainWindowMotion.settingsSidebarWidth)
                    .allowsHitTesting(settingsSidebarIsActive)
                    .accessibilityHidden(!settingsSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            case .network:
                networkSidebar
                    .frame(width: MainWindowMotion.networkSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(networkSidebarIsActive)
                    .accessibilityHidden(!networkSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            case .warp:
                warpSidebar
                    .frame(width: MainWindowMotion.warpSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(warpSidebarIsActive)
                    .accessibilityHidden(!warpSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            case .ops:
                opsSidebar
                    .frame(width: MainWindowMotion.opsSidebarWidth)
                    .opacity(sidebarVisible ? 1 : 0)
                    .allowsHitTesting(opsSidebarIsActive)
                    .accessibilityHidden(!opsSidebarIsActive)
                    .transition(MainWindowMotion.secondarySidebarTransition)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            switch mode {
            case .app:
                appDetail
                    .transition(MainWindowMotion.appDetailTransition)
                    .zIndex(1)
            case .linuxDo:
                linuxDoDetail
                    .transition(MainWindowMotion.linuxDoDetailTransition)
                    .zIndex(1)
            case .sessions:
                sessionsDetail
                    .transition(MainWindowMotion.sessionsDetailTransition)
                    .zIndex(1)
            case .configs:
                configsDetail
                    .transition(MainWindowMotion.configsDetailTransition)
                    .zIndex(1)
            case .memory:
                memoryDetail
                    .transition(MainWindowMotion.memoryDetailTransition)
                    .zIndex(1)
            case .chat:
                chatDetail
                    .transition(MainWindowMotion.chatDetailTransition)
                    .zIndex(1)
            case .settings:
                settingsDetail
                    .transition(MainWindowMotion.settingsDetailTransition)
                    .zIndex(1)
            case .network:
                networkDetail
                    .transition(MainWindowMotion.networkDetailTransition)
                    .zIndex(1)
            case .warp:
                warpDetail
                    .transition(MainWindowMotion.warpDetailTransition)
                    .zIndex(1)
            case .ops:
                opsDetail
                    .transition(MainWindowMotion.opsDetailTransition)
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Main window shell") {
    MainWindowModeShell(mode: .settings, sidebarVisible: true, boundaryFalloffEnabled: true) {
        VStack(alignment: .leading) {
            Text("App")
            Spacer()
            Text("Settings")
        }
        .padding()
    } linuxDoSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("LinuxDo")
            Spacer()
        }
        .padding()
    } sessionsSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Sessions")
            Spacer()
        }
        .padding()
    } configsSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Overview")
            Spacer()
        }
        .padding()
    } memorySidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Memory")
            Spacer()
        }
        .padding()
    } chatSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Chat")
            Spacer()
        }
        .padding()
    } settingsSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("General")
            Spacer()
        }
        .padding()
    } networkSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Traffic")
            Spacer()
        }
        .padding()
    } warpSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Sessions")
            Spacer()
        }
        .padding()
    } opsSidebar: {
        VStack(alignment: .leading) {
            Text("Back")
            Text("Ports")
            Spacer()
        }
        .padding()
    } appDetail: {
        Color.stxBackground.overlay(Text("App Detail"))
    } linuxDoDetail: {
        Color.stxBackground.overlay(Text("LinuxDo Detail"))
    } sessionsDetail: {
        Color.stxBackground.overlay(Text("Sessions Detail"))
    } configsDetail: {
        Color.stxBackground.overlay(Text("Config Detail"))
    } memoryDetail: {
        Color.stxBackground.overlay(Text("Memory Detail"))
    } chatDetail: {
        Color.stxBackground.overlay(Text("Chat Detail"))
    } settingsDetail: {
        Color.stxBackground.overlay(Text("Settings Detail"))
    } networkDetail: {
        Color.stxBackground.overlay(Text("Network Detail"))
    } warpDetail: {
        Color.stxBackground.overlay(Text("Warp Detail"))
    } opsDetail: {
        Color.stxBackground.overlay(Text("Ops Detail"))
    }
    .frame(width: 900, height: 600)
    .background(VisualEffectBackground())
}
#endif
