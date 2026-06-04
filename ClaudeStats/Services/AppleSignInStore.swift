@preconcurrency import AuthenticationServices
import Foundation
import Security

struct AppleSignInAccount: Codable, Equatable, Sendable {
    var userIdentifier: String
    var email: String?
    var fullName: String?
    var signedInAt: Date
    var lastCredentialStateCheckedAt: Date?

    var displayName: String {
        if let fullName, !fullName.isEmpty { return fullName }
        if let email, !email.isEmpty { return email }
        return "Apple Account"
    }
}

enum AppleSignInCredentialStatus: String, Equatable, Sendable {
    case unknown
    case authorized
    case revoked
    case notFound
    case transferred

    var displayText: String {
        switch self {
        case .unknown:
            return "Not checked"
        case .authorized:
            return "Signed in"
        case .revoked:
            return "Revoked"
        case .notFound:
            return "Not found"
        case .transferred:
            return "Transferred"
        }
    }
}

enum AppleSignInRuntimeEntitlements {
    private static let applicationIdentifierKey = "com.apple.application-identifier"
    private static let appleSignInKey = "com.apple.developer.applesignin"

    static func hasSignInWithAppleAccess() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let applicationIdentifier = entitlementValue(applicationIdentifierKey, task: task) as? String,
              !applicationIdentifier.isEmpty,
              let values = entitlementValue(appleSignInKey, task: task) as? [String],
              values.contains("Default") else {
            return false
        }
        return true
    }

    private static func entitlementValue(_ key: String, task: SecTask) -> Any? {
        SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }
}

@MainActor
@Observable
final class AppleSignInStore {
    private enum DefaultsKey {
        static let account = "appleSignInAccount"
    }

    private let defaults: UserDefaults
    private let entitlementChecker: @Sendable () -> Bool

    private(set) var account: AppleSignInAccount?
    private(set) var credentialStatus: AppleSignInCredentialStatus = .unknown
    private(set) var isSigningIn = false
    private(set) var isCheckingCredential = false
    private(set) var lastError: String?

    init(
        defaults: UserDefaults = .standard,
        entitlementChecker: @escaping @Sendable () -> Bool = AppleSignInRuntimeEntitlements.hasSignInWithAppleAccess
    ) {
        self.defaults = defaults
        self.entitlementChecker = entitlementChecker
        self.account = Self.readAccount(defaults: defaults)
    }

    var isRuntimeAvailable: Bool {
        entitlementChecker()
    }

    var isBusy: Bool {
        isSigningIn || isCheckingCredential
    }

    var statusText: String {
        if !isRuntimeAvailable {
            return "Unavailable in this build"
        }
        if isSigningIn {
            return "Signing in..."
        }
        if isCheckingCredential {
            return "Checking Apple account..."
        }
        if let lastError, !lastError.isEmpty {
            return lastError
        }
        guard account != nil else {
            return "Not signed in"
        }
        return credentialStatus.displayText
    }

    func start() {
        guard account != nil else { return }
        refreshCredentialState()
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func beginSignIn() {
        lastError = nil
        isSigningIn = true
    }

    func handleAuthorization(_ result: Result<ASAuthorization, any Error>) {
        defer { isSigningIn = false }

        guard isRuntimeAvailable else {
            lastError = "This build is missing Sign in with Apple entitlements."
            return
        }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                lastError = "Apple returned an unsupported credential."
                return
            }
            save(credential: credential)
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               ASAuthorizationError.Code(rawValue: nsError.code) == .canceled {
                lastError = nil
            } else {
                lastError = error.localizedDescription
            }
        }
    }

    func refreshCredentialState() {
        guard let account else { return }
        guard isRuntimeAvailable else {
            credentialStatus = .unknown
            lastError = "This build is missing Sign in with Apple entitlements."
            return
        }

        isCheckingCredential = true
        lastError = nil
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: account.userIdentifier) { [weak self] state, error in
            Task { @MainActor [weak self] in
                self?.handleCredentialState(state, error: error)
            }
        }
    }

    func signOut() {
        account = nil
        credentialStatus = .unknown
        lastError = nil
        defaults.removeObject(forKey: DefaultsKey.account)
    }

    private func save(credential: ASAuthorizationAppleIDCredential) {
        let existing = account?.userIdentifier == credential.user ? account : nil
        let fullName = formattedName(credential.fullName) ?? existing?.fullName
        let email = credential.email ?? existing?.email
        let next = AppleSignInAccount(
            userIdentifier: credential.user,
            email: email?.isEmpty == false ? email : nil,
            fullName: fullName?.isEmpty == false ? fullName : nil,
            signedInAt: existing?.signedInAt ?? Date(),
            lastCredentialStateCheckedAt: nil
        )

        account = next
        credentialStatus = .authorized
        lastError = nil
        writeAccount(next)
        refreshCredentialState()
    }

    private func handleCredentialState(_ state: ASAuthorizationAppleIDProvider.CredentialState, error: (any Error)?) {
        isCheckingCredential = false
        if let error {
            lastError = error.localizedDescription
            return
        }

        switch state {
        case .authorized:
            credentialStatus = .authorized
            touchCredentialCheckDate()
        case .revoked:
            credentialStatus = .revoked
            lastError = "Apple sign-in was revoked."
            clearPersistedAccount()
        case .notFound:
            credentialStatus = .notFound
            lastError = "Apple account authorization was not found."
            clearPersistedAccount()
        case .transferred:
            credentialStatus = .transferred
            touchCredentialCheckDate()
        @unknown default:
            credentialStatus = .unknown
            touchCredentialCheckDate()
        }
    }

    private func touchCredentialCheckDate() {
        guard var account else { return }
        account.lastCredentialStateCheckedAt = Date()
        self.account = account
        writeAccount(account)
    }

    private func clearPersistedAccount() {
        account = nil
        defaults.removeObject(forKey: DefaultsKey.account)
    }

    private func writeAccount(_ account: AppleSignInAccount) {
        do {
            let data = try JSONEncoder.appleSignInEncoder.encode(account)
            defaults.set(data, forKey: DefaultsKey.account)
        } catch {
            Log.app.error("Apple sign-in account save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func readAccount(defaults: UserDefaults) -> AppleSignInAccount? {
        guard let data = defaults.data(forKey: DefaultsKey.account) else { return nil }
        do {
            return try JSONDecoder.appleSignInDecoder.decode(AppleSignInAccount.self, from: data)
        } catch {
            Log.app.error("Apple sign-in account decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func formattedName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }
}

private extension JSONEncoder {
    static var appleSignInEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var appleSignInDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
