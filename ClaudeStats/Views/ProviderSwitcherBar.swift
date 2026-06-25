import SwiftUI

/// The row of platform logos shown at the top of the panel when more than one
/// platform is enabled — replaces the decorative ``TickBar`` in that case.
/// The selected platform gets full opacity and an accent underline; the rest
/// are dimmed and brighten on hover. A hairline below doubles as the loading
/// indicator the `TickBar` used to provide.
struct ProviderSwitcherBar: View {
    @Environment(AppEnvironment.self) private var env
    var interactive = true

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Text("[").foregroundStyle(Color.stxBracket)
                HStack(spacing: 14) {
                    ForEach(env.preferences.orderedEnabledProviders) { kind in
                        ProviderLogoButton(
                            kind: kind,
                            isSelected: kind == env.preferences.selectedProvider,
                            interactive: interactive
                        ) {
                            if env.preferences.selectedProvider != kind { env.preferences.selectedProvider = kind }
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("]").foregroundStyle(Color.stxBracket)
            }
            .font(.sora(11))
            LoadingLine(active: env.store.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 5)
        .animation(.easeOut(duration: 0.18), value: env.preferences.selectedProvider)
    }
}

private struct ProviderLogoButton: View {
    let kind: ProviderKind
    let isSelected: Bool
    let interactive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let content = VStack(spacing: 3) {
            Image(kind.monochromeAssetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
                .opacity(isSelected ? 1 : (hovering ? 0.7 : 0.32))
            Rectangle()
                .fill(Color.stxAccent)
                .frame(height: 1.5)
                .scaleEffect(x: isSelected ? 1 : 0, anchor: .center)
        }
        .contentShape(Rectangle())
        .help(kind.displayName)

        if interactive {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.18), value: isSelected)
                .animation(.easeOut(duration: 0.12), value: hovering)
        } else {
            content
        }
    }
}

/// A 1.5pt hairline that pulses in the accent colour while `active`.
private struct LoadingLine: View {
    let active: Bool
    @State private var lit = false

    var body: some View {
        Rectangle()
            .fill(active ? Color.stxAccent : Color.stxStroke)
            .opacity(active ? (lit ? 0.9 : 0.25) : 1)
            .frame(height: 1.5)
            .onAppear { syncAnimation() }
            .onChange(of: active) { _, _ in syncAnimation() }
    }

    private func syncAnimation() {
        if active {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { lit = true }
        } else {
            withAnimation(.default) { lit = false }
        }
    }
}

#if DEBUG
#Preview("Switcher") {
    let env = AppEnvironment.preview()
    env.preferences.enabledProviders = [.claude, .codex, .gemini, .opencode, .kiro, .hermes, .zcode]
    return VStack(spacing: 0) {
        ProviderSwitcherBar().environment(env)
        StxRule()
    }
    .frame(width: 380)
    .background(Color.stxBackground)
}
#endif
