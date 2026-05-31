import SwiftUI

struct OpsSidebarColumn: View {
    @Binding var section: OpsSection
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

            sectionHeader("OPS")

            ForEach(OpsSection.allCases) { item in
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

#if DEBUG
#Preview("Ops sidebar") {
    @Previewable @State var section: OpsSection = .ports
    return OpsSidebarColumn(section: $section, onExit: {})
        .frame(width: 240, height: 620)
        .background(VisualEffectBackground())
}
#endif
