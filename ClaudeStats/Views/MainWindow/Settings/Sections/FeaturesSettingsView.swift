import ApplicationServices
import AppKit
import SwiftUI

struct FeaturesSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var fullDiskAccessOK = ScreenTimeService.canRead()

    var onSelectSection: (SettingsSection) -> Void = { _ in }

    private let columns = [
        GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)
    ]

    var body: some View {
        @Bindable var prefs = env.preferences

        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            aiActivityCard(prefs: prefs)
            gitTrackingCard(prefs: prefs)
            systemMonitorCard(prefs: prefs)
            githubCard(prefs: prefs)
            leaderboardsCard(prefs: prefs)
            floatingTabCard(prefs: prefs)
            cursorCommandOverlayCard(prefs: prefs)
            if AppVariant.isEnabled(.notchIsland) {
                notchIslandCard(prefs: prefs)
            }
        }
    }

    private func aiActivityCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "AI Activity Analysis",
            symbol: AppIcon.Settings.tracking,
            description: "Compares coding apps, terminal hosts, and AI-assisted overlap using local Screen Time data.",
            status: prefs.aiActivityAnalysisEnabled ? fullDiskAccessStatus : "Hidden from Stats",
            isOn: $prefs.aiActivityAnalysisEnabled,
            onConfigure: { onSelectSection(.tracking) }
        ) {
            ActivityFeaturePreview()
        }
    }

    private func gitTrackingCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "Git Tracking",
            symbol: AppIcon.Workspace.git,
            description: "Reads local commit history for repos used with Claude and correlates code churn with sessions.",
            status: prefs.gitTrackingEnabled ? gitTrackingStatus(prefs: prefs) : "Hidden from Tools",
            isOn: $prefs.gitTrackingEnabled,
            onConfigure: { onSelectSection(.tracking) }
        ) {
            GitTrackingFeaturePreview()
        }
    }

    private func systemMonitorCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "System Monitor",
            symbol: AppIcon.Workspace.system,
            description: "Shows read-only CPU, memory, disk, network, battery, GPU, and thermal sampling on demand.",
            status: prefs.systemMonitorEnabled ? systemMonitorStatus(prefs: prefs) : "Hidden from Stats",
            isOn: $prefs.systemMonitorEnabled,
            onConfigure: { onSelectSection(.systemMonitor) }
        ) {
            SystemMonitorFeaturePreview()
        }
    }

    private func githubCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "GitHub Comparison",
            symbol: AppIcon.Git.code,
            description: "Adds a GitHub heatmap and local-vs-GitHub overlap view to the Dashboard.",
            status: prefs.githubEnabled ? githubStatus : "Dashboard comparison off",
            isOn: $prefs.githubEnabled,
            onConfigure: { onSelectSection(.github) }
        ) {
            GitHubFeaturePreview()
        }
    }

    private func leaderboardsCard(prefs: Preferences) -> some View {
        FeatureControlCard(
            title: "CloudKit Leaderboards",
            symbol: AppIcon.Workspace.leaderboards,
            description: "Publishes privacy-preserving aggregate scores to CloudKit's public database.",
            status: prefs.leaderboardsEnabled ? env.leaderboards.syncStatus.displayText : "Not joined",
            isOn: leaderboardsBinding(prefs: prefs),
            onConfigure: { onSelectSection(.leaderboards) }
        ) {
            LeaderboardsFeaturePreview()
        }
    }

    private func floatingTabCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "Floating Edge Tab",
            symbol: AppIcon.Layout.overlap,
            description: "Keeps Claude Stats reachable from a small screen-edge tab when the menu bar is crowded.",
            status: prefs.floatingTabEnabled ? "Docked on \(prefs.floatingTabEdge.rawValue.capitalized)" : "Off",
            isOn: $prefs.floatingTabEnabled,
            onConfigure: { onSelectSection(.menuBar) }
        ) {
            FloatingTabFeaturePreview()
        }
    }

    private func cursorCommandOverlayCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "Cursor Commands",
            symbol: AppIcon.Runtime.terminalFilled,
            description: "Shows recent session commands next to the active text cursor, with copy-only command actions.",
            status: cursorCommandOverlayStatus(prefs: prefs),
            isOn: cursorCommandOverlayBinding(prefs: prefs),
            onConfigure: nil
        ) {
            CursorCommandOverlayFeaturePreview()
        } controls: {
            VStack(alignment: .leading, spacing: 10) {
                if !AXIsProcessTrusted() {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: AppIcon.Feature.accessibility)
                            .foregroundStyle(Color.stxAccent)
                            .frame(width: 18, height: 18)
                        Text("Grant Accessibility access so Claude Stats can find the focused text cursor. The overlay will stay hidden until access is available.")
                            .font(.sora(11))
                            .foregroundStyle(Color.stxMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Open Accessibility") {
                            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                            CursorTextFocusLocator.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                } else {
                    Label("Accessibility access is available.", systemImage: AppIcon.Status.success)
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                }
            }
        }
    }

    private func notchIslandCard(prefs: Preferences) -> some View {
        @Bindable var prefs = prefs
        return FeatureControlCard(
            title: "Notch Island",
            symbol: AppIcon.NotchIsland.island,
            description: "Adds an Atoll-backed Dynamic Island surface around the camera notch while keeping existing app entry points.",
            status: prefs.notchIslandEnabled ? notchIslandStatus(prefs: prefs) : "Off",
            isOn: $prefs.notchIslandEnabled,
            onConfigure: { onSelectSection(.notchIsland) }
        ) {
            NotchIslandFeaturePreview()
        }
    }

    private var fullDiskAccessStatus: String {
        fullDiskAccessOK ? "Full Disk Access granted" : "Needs Full Disk Access"
    }

    private func gitTrackingStatus(prefs: Preferences) -> String {
        prefs.gitOpensInWindow ? "Separate window" : "Panel tab"
    }

    private func systemMonitorStatus(prefs: Preferences) -> String {
        let count = prefs.systemMonitorVisibleModules.count
        return "\(prefs.systemMonitorRefreshRate.displayName) - \(count) modules"
    }

    private func notchIslandStatus(prefs: Preferences) -> String {
        "\(prefs.notchIslandSizePreset.displayName) - \(prefs.notchIslandEnabledModules.count) modules"
    }

    private func cursorCommandOverlayStatus(prefs: Preferences) -> String {
        guard prefs.cursorCommandOverlayEnabled else { return "Off" }
        return AXIsProcessTrusted() ? "Ready near text cursor" : "Needs Accessibility"
    }

    private func cursorCommandOverlayBinding(prefs: Preferences) -> Binding<Bool> {
        Binding(
            get: { prefs.cursorCommandOverlayEnabled },
            set: { enabled in
                prefs.cursorCommandOverlayEnabled = enabled
                if enabled, !AXIsProcessTrusted() {
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            }
        )
    }

    private var githubStatus: String {
        switch env.github.status {
        case .disconnected:
            return "Not connected"
        case .connecting:
            return "Connecting"
        case .connected(let login, _, _):
            return "@\(login)"
        case .failed:
            return "Needs attention"
        }
    }

    private func leaderboardsBinding(prefs: Preferences) -> Binding<Bool> {
        Binding(
            get: { prefs.leaderboardsEnabled },
            set: { enabled in
                prefs.leaderboardsEnabled = enabled
                Task {
                    if enabled {
                        await env.leaderboards.syncIfDue(force: false)
                    } else {
                        await env.leaderboards.checkAccountStatus()
                    }
                }
            }
        )
    }

}

private struct ActivityFeaturePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Activity", systemImage: AppIcon.Workspace.activity)
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("Today")
                    .font(.sora(10, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }

            HStack(spacing: 8) {
                PreviewMetric(title: "Surface", value: "4h 12m")
                PreviewMetric(title: "AI Active", value: "2h 37m")
                PreviewMetric(title: "Overlap", value: "61%")
            }

            VStack(alignment: .leading, spacing: 6) {
                PreviewLane(label: "IDE", color: Color.primary.opacity(0.28), widths: [0.42, 0.24, 0.18])
                PreviewLane(label: "CLI", color: Color.blue.opacity(0.46), widths: [0.22, 0.18, 0.36])
                PreviewLane(label: "AI", color: Color.stxAccent.opacity(0.68), widths: [0.31, 0.24, 0.22])
            }
        }
    }
}

private struct GitTrackingFeaturePreview: View {
    private let rows = [
        ("aurora", "9 commits", 0.92),
        ("ledger", "4 commits", 0.54),
        ("design-system", "3 commits", 0.38),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Repository activity", systemImage: AppIcon.Resource.folder)
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("+1.8k")
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            ForEach(rows, id: \.0) { row in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.0)
                            .font(.sora(11, weight: .medium))
                        Spacer()
                        Text(row.1)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.stxAccent.opacity(0.72))
                                    .frame(width: proxy.size.width * row.2)
                            }
                    }
                    .frame(height: 7)
                }
            }
        }
    }
}

private struct SystemMonitorFeaturePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("System", systemImage: AppIcon.Workspace.system)
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("3s")
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            HStack(spacing: 8) {
                SystemPreviewTile(title: "CPU", value: "42%", colors: [Color.stxRamp[1], Color.stxRamp[0]])
                SystemPreviewTile(title: "Memory", value: "64%", colors: [Color.stxRamp[0], Color.stxRamp[3]])
                SystemPreviewTile(title: "Net", value: "1.8M", colors: [Color.stxRamp[3], Color.stxRamp[0]])
            }
        }
    }
}

private struct GitHubFeaturePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Overlap", systemImage: AppIcon.Layout.grid3)
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("90d")
                    .font(.sora(10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }

            PreviewHeatmap(colors: colors)

            HStack(spacing: 8) {
                legend("Both", Color.stxAccent)
                legend("Local", Color.primary.opacity(0.44))
                legend("GitHub", Color.green.opacity(0.72))
            }
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
    }

    private var colors: [Color] {
        (0..<70).map { index in
            switch index % 9 {
            case 0, 4: Color.stxAccent
            case 2, 7: Color.green.opacity(0.72)
            case 5: Color.primary.opacity(0.44)
            default: Color.primary.opacity(0.08)
            }
        }
    }
}

private struct LeaderboardsFeaturePreview: View {
    private let rows = [
        ("Ada", "1.42M", "1"),
        ("Claude", "1.18M", "2"),
        ("You", "924K", "3"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Leaderboard", systemImage: AppIcon.Workspace.leaderboards)
                    .font(.sora(12, weight: .semibold))
                Spacer()
                Text("Daily")
                    .font(.sora(10, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }

            ForEach(rows, id: \.0) { row in
                HStack(spacing: 8) {
                    Text("#\(row.2)")
                        .font(.sora(10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                        .frame(width: 26, alignment: .leading)
                    BeamAvatarView(seed: "features-\(row.0)", size: 24, isDecorative: true)
                    Text(row.0)
                        .font(.sora(11, weight: .medium))
                    Spacer()
                    Text(row.1)
                        .font(.sora(11, weight: .semibold).monospacedDigit())
                }
            }
        }
    }
}

private struct FloatingTabFeaturePreview: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.stxStroke, lineWidth: 1)
                }
                .overlay(alignment: .trailing) {
                    VStack(spacing: 0) {
                        Text("claude")
                            .font(.sora(11, weight: .semibold))
                            .tracking(0.8)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 76, height: 24)
                    }
                    .frame(width: 28, height: 88)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.stxStroke, lineWidth: 1))
                    .padding(.trailing, -7)
                }

            VStack(alignment: .leading, spacing: 8) {
                PreviewMetric(title: "Tokens", value: "119M")
                PreviewMetric(title: "Cost", value: "$42")
            }
            .frame(width: 92)
        }
    }
}

private struct CursorCommandOverlayFeaturePreview: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(Color.stxMuted.opacity(0.45)).frame(width: 6, height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(Color.stxMuted.opacity(0.18)).frame(width: 86, height: 8)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.16)).frame(width: 210, height: 9)
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.10)).frame(width: 164, height: 9)
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.stxAccent).frame(width: 2, height: 18)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.stxAccent.opacity(0.18))
                            .frame(width: 30, height: 28)
                            .overlay {
                                Image(systemName: AppIcon.Runtime.terminalFilled)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.stxAccent)
                            }
                    }
                    .padding(.top, 2)
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(["git status", "bash scripts/run-tests.sh", "rg command"], id: \.self) { command in
                        Text(command)
                            .font(.system(size: 8, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct NotchIslandFeaturePreview: View {
    var body: some View {
        VStack(spacing: 12) {
            UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 6,
                style: .continuous
            )
            .fill(Color.black)
            .frame(width: 188, height: 34)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

            HStack(spacing: 24) {
                ForEach([AppIcon.NotchIsland.previewHome, AppIcon.Resource.trayFilled, AppIcon.NotchIsland.timer, AppIcon.NotchIsland.previewUsage], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(symbol == AppIcon.NotchIsland.previewHome ? Color.primary : Color.stxMuted)
                        .frame(width: 26, height: 26)
                        .background {
                            if symbol == AppIcon.NotchIsland.previewHome {
                                Capsule()
                                    .fill(Color.primary.opacity(0.12))
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct PreviewLane: View {
    let label: String
    let color: Color
    let widths: [CGFloat]

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.sora(9, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 24, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    HStack(spacing: 4) {
                        ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                            Capsule()
                                .fill(color.opacity(index == 1 ? 0.82 : 0.56))
                                .frame(width: proxy.size.width * width)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(height: 9)
        }
    }
}

private struct SystemPreviewTile: View {
    let title: String
    let value: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(15, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            SystemTimelineChart(
                bars: (0..<18).map { index in
                    colors.enumerated().map { offset, color in
                        let base = 0.08 + Double((index + offset * 2) % 7) * 0.018
                        return SystemTimelineSegment(value: base, color: color)
                    }
                },
                placeholderCount: 18
            )
            .frame(height: 42)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct PreviewHeatmap: View {
    let colors: [Color]

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<7, id: \.self) { row in
                GridRow {
                    ForEach(0..<10, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[(column * 7 + row) % colors.count])
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    FeaturesSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 900)
        .background(Color.stxBackground)
}
#endif
