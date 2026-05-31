import SwiftUI

struct FeatureControlCard<Preview: View, Controls: View>: View {
    let title: String
    let symbol: String
    let description: String
    let status: String
    @Binding var isOn: Bool
    var onConfigure: (() -> Void)?
    private let showsControls: Bool
    private let preview: Preview
    private let controls: Controls

    init(
        title: String,
        symbol: String,
        description: String,
        status: String,
        isOn: Binding<Bool>,
        onConfigure: (() -> Void)? = nil,
        showsControls: Bool = true,
        @ViewBuilder preview: () -> Preview,
        @ViewBuilder controls: () -> Controls
    ) {
        self.title = title
        self.symbol = symbol
        self.description = description
        self.status = status
        self._isOn = isOn
        self.onConfigure = onConfigure
        self.showsControls = showsControls
        self.preview = preview()
        self.controls = controls()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
                .frame(height: 152)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.stxAccent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(title))
                        .font(.sora(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(LocalizedStringKey(description))
                        .font(.sora(11))
                        .foregroundStyle(Color.stxMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.appSwitch)
                    .accessibilityLabel(title)
            }

            HStack(spacing: 10) {
                FeatureStatusPill(text: status, isEnabled: isOn)
                Spacer(minLength: 8)
                if let onConfigure {
                    Button(action: onConfigure) {
                        Label("Configure", systemImage: AppIcon.Workspace.configs)
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.small)
                }
            }

            if isOn && showsControls {
                StxRule()
                controls
            }
        }
        .appSurface(.mainWindowCard, padding: 16)
    }
}

extension FeatureControlCard where Controls == EmptyView {
    init(
        title: String,
        symbol: String,
        description: String,
        status: String,
        isOn: Binding<Bool>,
        onConfigure: (() -> Void)? = nil,
        @ViewBuilder preview: () -> Preview
    ) {
        self.init(
            title: title,
            symbol: symbol,
            description: description,
            status: status,
            isOn: isOn,
            onConfigure: onConfigure,
            showsControls: false,
            preview: preview,
            controls: { EmptyView() }
        )
    }
}

struct FeatureDisabledNotice: View {
    let featureName: String
    let message: String
    let onOpenFeatures: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: AppIcon.Action.quit)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.stxAccent)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(featureName) is off")
                    .font(.sora(13, weight: .semibold))
                Text(LocalizedStringKey(message))
                    .font(.sora(11))
                    .foregroundStyle(Color.stxMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Button("Open Features", action: onOpenFeatures)
                .controlSize(.small)
        }
        .padding(14)
        .settingCard()
    }
}

extension View {
    func disabledSettingsBlock(_ disabled: Bool) -> some View {
        modifier(DisabledSettingsBlockModifier(disabled: disabled))
    }
}

private struct DisabledSettingsBlockModifier: ViewModifier {
    let disabled: Bool

    func body(content: Content) -> some View {
        content
            .disabled(disabled)
            .opacity(disabled ? 0.48 : 1)
    }
}

private struct FeatureStatusPill: View {
    let text: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isEnabled ? Color.green : Color.stxMuted)
                .frame(width: 6, height: 6)
            Text(LocalizedStringKey(text))
                .font(.sora(10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(isEnabled ? .primary : Color.stxMuted)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.stxStroke, lineWidth: 1))
    }
}
