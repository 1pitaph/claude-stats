import SwiftUI

struct TrackSidebarColumn: View {
    @Bindable var store: TrackStore
    @Binding var section: TrackSection
    var onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: AppIcon.Navigation.back,
                isSelected: false,
                action: onExit
            )

            summaryCard
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 10)

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            sectionHeader("TRACK")

            ForEach(TrackSection.allCases) { item in
                SidebarRow(
                    title: item.title,
                    symbol: item.symbol,
                    isSelected: section == item
                ) {
                    section = item
                }
            }

            sectionHeader("RUNS")

            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.filteredRuns) { run in
                        TrackRunSidebarRow(
                            run: run,
                            isSelected: store.selectedRun?.id == run.id
                        ) {
                            store.selectRun(run)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .padding(.bottom, 10)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("AGENT TRACK")
                    .font(.sora(10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.stxMuted)
                Spacer(minLength: 8)
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 12) {
                metric("\(store.snapshot.activeCount)", "active")
                metric("\(store.snapshot.pendingApprovalCount)", "approval")
                metric("\(store.snapshot.runs.count)", "runs")
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.sora(18, weight: .semibold).monospacedDigit())
                .lineLimit(1)
            Text(label)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: AppIcon.Action.search)
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
                .accessibilityHidden(true)
            TextField("Search runs", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: AppIcon.Action.clear)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

private struct TrackRunSidebarRow: View {
    let run: TrackRun
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(run.status.trackColor)
                        .frame(width: 7, height: 7)
                    Text(run.projectName)
                        .font(.sora(11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(run.provider?.shortName ?? run.confidence.titleShort)
                        .font(.sora(9, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }

                Text(run.title)
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    label(run.status.title)
                    if run.pendingApprovalCount > 0 { label("\(run.pendingApprovalCount) approval") }
                    if run.subagentCount > 0 { label("\(run.subagentCount) agents") }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(rowStroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(run.title)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.sora(9, weight: .medium))
            .foregroundStyle(Color.stxMuted)
            .lineLimit(1)
    }

    private var rowBackground: Color {
        isSelected ? Color.stxAccent.opacity(0.13) : Color.primary.opacity(0.035)
    }

    private var rowStroke: Color {
        isSelected ? Color.stxAccent.opacity(0.35) : Color.stxStroke.opacity(0.5)
    }
}

extension TrackConfidence {
    var titleShort: String {
        switch self {
        case .low: "low"
        case .medium: "med"
        case .high: "high"
        }
    }
}
