@preconcurrency import AuthenticationServices
import SwiftUI

struct AppleAccountSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingGroup(
            title: "Apple Account",
            caption: "Connect your Apple Account for Sign in with Apple and future private iCloud sync."
        ) {
            VStack(spacing: 0) {
                SettingRow(
                    title: "Sign in with Apple",
                    description: accountDescription
                ) {
                    accessory
                }
                if let notice {
                    SettingRowDivider()
                    Text(notice)
                        .font(.sora(11))
                        .foregroundStyle(noticeColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .settingCard()
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if let account = env.appleSignIn.account {
            HStack(spacing: 10) {
                if env.appleSignIn.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
                VStack(alignment: .trailing, spacing: 3) {
                    Text(account.displayName)
                        .font(.sora(12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(env.appleSignIn.statusText)
                        .font(.sora(11))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: 220, alignment: .trailing)

                Button("Refresh") {
                    env.appleSignIn.refreshCredentialState()
                }
                .disabled(env.appleSignIn.isBusy || !env.appleSignIn.isRuntimeAvailable)

                Button("Sign out") {
                    env.appleSignIn.signOut()
                }
                .disabled(env.appleSignIn.isBusy)
            }
        } else {
            HStack(spacing: 10) {
                if env.appleSignIn.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
                signInButton
            }
        }
    }

    private var signInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            env.appleSignIn.beginSignIn()
            env.appleSignIn.configure(request)
        } onCompletion: { result in
            env.appleSignIn.handleAuthorization(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(width: 180, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .disabled(env.appleSignIn.isBusy || !env.appleSignIn.isRuntimeAvailable)
        .opacity(env.appleSignIn.isRuntimeAvailable ? 1 : 0.55)
    }

    private var accountDescription: String {
        if let account = env.appleSignIn.account {
            return "Signed in locally as \(account.displayName)."
        }
        return "Use your Apple Account to prepare Claude Stats for private iCloud reuse across your Macs."
    }

    private var notice: String? {
        if !env.appleSignIn.isRuntimeAvailable {
            return "Sign in with Apple requires a signed build with the Apple Sign In capability."
        }
        if let lastError = env.appleSignIn.lastError, !lastError.isEmpty {
            return lastError
        }
        return nil
    }

    private var noticeColor: Color {
        env.appleSignIn.isRuntimeAvailable ? Color.stxAccent : Color.stxMuted
    }

    private var statusColor: Color {
        switch env.appleSignIn.credentialStatus {
        case .authorized:
            return Color.stxMuted
        case .revoked, .notFound:
            return Color.stxAccent
        case .unknown, .transferred:
            return Color.stxMuted
        }
    }
}

#if DEBUG
#Preview {
    AppleAccountSettingsView()
        .environment(AppEnvironment.preview())
        .padding()
        .frame(width: 720)
}
#endif
