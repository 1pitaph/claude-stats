import SwiftUI

struct AIConfigsOverviewView: View {
    let searchText: String

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryGrid
                planSummary
                coverageSummary
                diagnosticsSummary
                projectSummary
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
    }

    private var summaryGrid: some View {
        let summary = env.aiConfigs.snapshot.summary
        return LazyVGrid(columns: metricColumns, spacing: 12) {
            AIConfigsMetricCard(title: "Files", value: "\(summary.existingDocumentCount)", symbol: AppIcon.Resource.documentText)
            AIConfigsMetricCard(title: "Projects", value: "\(summary.projectCount)", symbol: AppIcon.Resource.folder)
            AIConfigsMetricCard(title: "Plans", value: "\(summary.planStats.total)", symbol: AppIcon.AIConfig.plan)
            AIConfigsMetricCard(
                title: "Diagnostics",
                value: "\(summary.diagnosticCount)",
                symbol: AppIcon.Status.warning,
                tint: summary.diagnosticCount > 0 ? Color(red: 0.92, green: 0.58, blue: 0.16) : Color.stxAccent
            )
        }
    }

    private var planSummary: some View {
        let stats = env.aiConfigs.snapshot.summary.planStats
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Plan Ownership", symbol: AppIcon.AIConfig.plan)
            LazyVGrid(columns: metricColumns, spacing: 12) {
                AIConfigsMetricCard(title: "Assigned", value: "\(stats.assigned)", symbol: AppIcon.Resource.configuredFolder)
                AIConfigsMetricCard(title: "Unassigned", value: "\(stats.unassigned)", symbol: AppIcon.Resource.tray)
                AIConfigsMetricCard(title: "Open Tasks", value: "\(stats.uncheckedTasks)", symbol: AppIcon.Status.uncheckedTask)
                AIConfigsMetricCard(title: "Done Tasks", value: "\(stats.checkedTasks)", symbol: AppIcon.Status.checkedTask)
            }
        }
        .mainWindowPanel()
    }

    private var coverageSummary: some View {
        let summary = env.aiConfigs.snapshot.summary
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Coverage", symbol: AppIcon.AIConfig.scope)
            HStack(spacing: 12) {
                coverageRow(title: "Existing", count: summary.existingDocumentCount, tint: Color.stxAccent)
                coverageRow(title: "Missing Expected", count: summary.missingExpectedCount, tint: Color.stxMuted)
                coverageRow(title: "Total Sources", count: summary.documentCount, tint: Color.stxMuted)
            }
        }
        .mainWindowPanel()
    }

    private var diagnosticsSummary: some View {
        let diagnosticsProjects = env.aiConfigs.filteredProjects(section: .diagnostics, query: searchText)
        let documents = diagnosticsProjects.flatMap(\.documents)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Diagnostics", symbol: AppIcon.Status.warning)
            if documents.isEmpty {
                Text(searchText.isEmpty ? "No config diagnostics." : "No diagnostics match the current search.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(documents.prefix(5)) { document in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: document.diagnostics.contains(where: { $0.severity == .error }) ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                                .foregroundStyle(document.diagnostics.contains(where: { $0.severity == .error }) ? Color(red: 0.85, green: 0.22, blue: 0.18) : Color(red: 0.92, green: 0.58, blue: 0.16))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.title)
                                    .font(.sora(11, weight: .semibold))
                                    .lineLimit(1)
                                Text(document.diagnostics.first?.message ?? "Diagnostic available")
                                    .font(.sora(10))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            AIConfigsBadge(text: "\(document.diagnostics.count)", color: Color.stxMuted)
                        }
                    }
                }
            }
        }
        .mainWindowPanel()
    }

    private var projectSummary: some View {
        let projects = env.aiConfigs
            .filteredProjects(section: .overview, query: searchText)
            .sorted {
                if $0.summary.existingDocumentCount != $1.summary.existingDocumentCount {
                    return $0.summary.existingDocumentCount > $1.summary.existingDocumentCount
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Scopes", symbol: AppIcon.Resource.folder)
            if projects.isEmpty {
                Text(searchText.isEmpty ? "No config scopes discovered yet." : "No scopes match the current search.")
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(projects.prefix(8)) { project in
                        HStack(spacing: 10) {
                            Image(systemName: project.configsIconName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.stxMuted)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.sora(11, weight: .semibold))
                                    .lineLimit(1)
                                Text(project.configsDetailText)
                                    .font(.sora(9))
                                    .foregroundStyle(Color.stxMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            AIConfigsMiniStat(value: "\(project.summary.existingDocumentCount)", label: "files")
                            AIConfigsMiniStat(value: "\(project.summary.diagnosticCount)", label: "issues")
                        }
                    }
                }
            }
        }
        .mainWindowPanel()
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
            Text(title)
                .font(.sora(14, weight: .semibold))
            Spacer(minLength: 0)
        }
    }

    private func coverageRow(title: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.sora(8, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Color.stxMuted)
            Text("\(count)")
                .font(.sora(18, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}
