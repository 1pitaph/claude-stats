import SwiftUI
import WarpEmbed

struct WarpSidebarColumn: View {
    @ObservedObject var store: WarpSessionStore
    @Binding var section: WarpWorkspaceSection
    var onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)

            SidebarRow(
                title: "Back to App",
                symbol: "chevron.left",
                isSelected: false,
                action: onExit
            )

            statusCard
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 10)

            sectionHeader("WARP")

            ForEach(WarpWorkspaceSection.allCases) { item in
                SidebarRow(
                    title: item.title,
                    symbol: item.symbol,
                    isSelected: section == item
                ) {
                    section = item
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 10)
        .onAppear {
            store.ensureDefaultSession()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: store.availability.isReady ? "checkmark.circle.fill" : "wrench.and.screwdriver")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(store.availability.isReady ? Color.green : Color.stxMuted)
                Text(store.availability.isReady ? "Bridge Ready" : "Bridge Pending")
                    .font(.sora(11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            Text(store.availability.message)
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .font(.sora(10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(Color.stxMuted)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 4)
    }
}

#if DEBUG
#Preview("Warp sidebar") {
    @Previewable @State var section: WarpWorkspaceSection = .sessions
    return WarpSidebarColumn(store: WarpSessionStore(), section: $section, onExit: {})
        .frame(width: 240, height: 620)
        .background(VisualEffectBackground())
}
#endif
