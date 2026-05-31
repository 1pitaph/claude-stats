import SwiftUI

/// A tappable header row for one project: folder glyph, project name, session
/// count, and a disclosure chevron that rotates when the group is expanded.
struct ProjectGroupRow: View {
    let group: SessionListViewModel.ProjectGroup
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: AppIcon.Resource.folder)
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 18)

                Text(group.displayName)
                    .font(.sora(12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(group.count)")
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                Image(systemName: AppIcon.Navigation.disclosure)
                    .font(.sora(9, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    let samples = Session.previewSamples
    let group = SessionListViewModel.ProjectGroup(
        id: samples.first?.projectDirectoryName ?? "demo",
        displayName: samples.first?.projectDisplayName ?? "demo",
        sessions: samples,
        lastActivity: .now
    )
    return VStack(spacing: 0) {
        ProjectGroupRow(group: group, isExpanded: false) {}.padding(8)
        ProjectGroupRow(group: group, isExpanded: true) {}.padding(8)
    }
    .frame(width: 380)
    .background(Color.stxBackground)
    .preferredColorScheme(.dark)
}
#endif
