import SwiftUI

/// Settings-mode sidebar: a "Back to App" button at the top (clearing the
/// traffic-light area) followed by one row per `SettingsSection`. Mirrors
/// the layout of `SidebarColumn` and reuses the shared `SidebarRow`.
struct SettingsSidebarColumn: View {
    @Binding var section: SettingsSection
    var onExit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clear the traffic-light buttons.
            Color.clear.frame(height: 44)

            SidebarRow(title: "Back to App",
                       symbol: AppIcon.Navigation.back,
                       isSelected: false,
                       action: onExit)

            sectionHeader("SETTINGS")

            ForEach(SettingsSection.allCases) { s in
                SidebarRow(title: s.title,
                           symbol: s.symbol,
                           assetName: s.assetName,
                           isSelected: section == s) { section = s }
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
#Preview("Settings sidebar") {
    @Previewable @State var section: SettingsSection = .general
    return SettingsSidebarColumn(section: $section, onExit: {})
        .frame(width: 220, height: 600)
        .background(VisualEffectBackground())
}
#endif
