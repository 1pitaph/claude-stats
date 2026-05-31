import AppKit
import SwiftUI

/// Wide Activity page for the main window. The compact menu-bar panel and share
/// export keep using `AIActivityView`; this view owns the desktop layout.
struct MainActivityView: View {
    @Environment(AppEnvironment.self) private var env

    @SceneStorage("mainWindow.activity.range") private var rangeRaw: String = ActivityRange.day.rawValue
    @SceneStorage("mainWindow.activity.selectedDay") private var selectedDayReference: Double = Date.now.timeIntervalSinceReferenceDate

    @State private var vm = AIActivityViewModel()

    private struct ReloadKey: Equatable {
        let range: ActivityRange
        let selectedDay: Date
        let token: UInt64
        let lastRefreshed: Date?
        let codingSurfaceBundleIDs: Set<String>
        let cliHostBundleIDs: Set<String>
        let provider: ProviderKind
    }

    var body: some View {
        @Bindable var bvm = vm
        let provider = env.preferences.selectedProvider
        let codingSurfaceBundleIDs = env.preferences.effectiveCodingSurfaceBundleIDs
        let cliHostBundleIDs = env.preferences.effectiveCLIHostBundleIDs

        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(provider: provider)
                ActivityControls(
                    range: $bvm.range,
                    selectedDay: vm.selectedDay,
                    canStepForward: vm.canStepForward,
                    isLoading: vm.isLoading,
                    onStepDay: vm.stepDay
                )

                if vm.permissionState == .needsFullDiskAccess {
                    permissionGate
                } else if vm.range.isTrend {
                    trendBody
                } else {
                    dayBody
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 52)
            .padding(.bottom, 22)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            syncFromSceneStorage()
            vm.refreshPermissionState()
        }
        .onChange(of: vm.range) { _, new in
            rangeRaw = new.rawValue
        }
        .onChange(of: vm.selectedDay) { _, new in
            selectedDayReference = normalizedDay(new).timeIntervalSinceReferenceDate
        }
        .task(id: reloadKey(provider: provider, codingSurfaceBundleIDs: codingSurfaceBundleIDs, cliHostBundleIDs: cliHostBundleIDs)) {
            await vm.reload(
                sessions: env.store.sessions(for: provider),
                codingSurfaceBundleIDs: codingSurfaceBundleIDs,
                cliHostBundleIDs: cliHostBundleIDs
            )
        }
    }

    private var dayBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            ActivitySummaryCards(
                metrics: .day(vm.dayActivity),
                assistedLabel: "AI-assisted"
            )
            ActivityTimelinePanel(activity: vm.dayActivity)
            ActivityCompositionPanel(activity: vm.dayActivity)
        }
    }

    private var trendBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            ActivitySummaryCards(
                metrics: .trend(vm.trend),
                assistedLabel: "Avg AI-assisted"
            )
            ActivityTrendPanel(days: vm.trend)
            trendLowerPanels
        }
    }

    private var trendLowerPanels: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ActivityDailyBreakdownPanel(days: vm.trend)
                    .frame(minWidth: 560, maxWidth: .infinity)
                ActivityCompositionPanel(trend: vm.trend)
                    .frame(width: 300)
            }

            VStack(alignment: .leading, spacing: 12) {
                ActivityDailyBreakdownPanel(days: vm.trend)
                ActivityCompositionPanel(trend: vm.trend)
            }
        }
    }

    private func header(provider: ProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACTIVITY")
                .font(.sora(11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.stxMuted)
            Text("AI-assisted focus")
                .font(.sora(24, weight: .semibold))
                .lineLimit(1)
            Text("Coding-surface focus, CLI host time, and AI bursts for \(provider.displayName).")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
    }

    private var permissionGate: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("FULL DISK ACCESS REQUIRED")
                    .font(.sora(13, weight: .semibold))
                    .tracking(1.0)
                Spacer()
                Image(systemName: AppIcon.Status.lockShield)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .accessibilityHidden(true)
            }

            Text("Claude Stats reads macOS Screen Time to see when your coding surfaces and CLI hosts were focused. macOS protects that database behind Full Disk Access.")
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Open Full Disk Access settings") {
                    openFullDiskAccessSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Re-check") {
                    vm.refreshPermissionState()
                    vm.bumpReload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.sora(11))
        }
        .mainWindowPanel(padding: 16)
    }

    private func reloadKey(
        provider: ProviderKind,
        codingSurfaceBundleIDs: Set<String>,
        cliHostBundleIDs: Set<String>
    ) -> ReloadKey {
        ReloadKey(
            range: vm.range,
            selectedDay: vm.selectedDay,
            token: vm.reloadToken,
            lastRefreshed: env.store.lastRefreshedAt,
            codingSurfaceBundleIDs: codingSurfaceBundleIDs,
            cliHostBundleIDs: cliHostBundleIDs,
            provider: provider
        )
    }

    private func syncFromSceneStorage() {
        vm.range = ActivityRange(rawValue: rangeRaw) ?? .day
        vm.selectedDay = clampedDay(fromReference: selectedDayReference)
        selectedDayReference = vm.selectedDay.timeIntervalSinceReferenceDate
        rangeRaw = vm.range.rawValue
    }

    private func clampedDay(fromReference reference: Double) -> Date {
        let stored = Date(timeIntervalSinceReferenceDate: reference)
        let day = normalizedDay(stored)
        return min(day, vm.today)
    }

    private func normalizedDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
#Preview("Main Activity") {
    MainActivityView()
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
        .background(Color.stxBackground)
}
#endif
