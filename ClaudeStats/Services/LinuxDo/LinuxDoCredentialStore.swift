import Foundation
import Security

protocol LinuxDoCredentialStoring: Sendable {
    func deleteLegacyUserAPIKey()
    func readWebSession() -> LinuxDoWebSession?
    func saveWebSession(_ session: LinuxDoWebSession) throws
    func deleteWebSession()
}

extension LinuxDoCredentialStoring {
    func readAuthCredential() -> LinuxDoAuthCredential? {
        if let session = readWebSession(), session.isAuthenticated {
            return .webSession(session)
        }
        return nil
    }
}

struct LinuxDoKeychainStore: LinuxDoCredentialStoring {
    static let shared = LinuxDoKeychainStore()

    private let service = "com.claudestats.linuxdo"
    private let legacyAPIKeyAccount = "linux.do:default"
    private let legacyClientIDKey = "LinuxDo.clientID"
    private let webSessionAccount = "linux.do:web-session"

    func deleteLegacyUserAPIKey() {
        delete(account: legacyAPIKeyAccount)
        UserDefaults.standard.removeObject(forKey: legacyClientIDKey)
    }

    func readWebSession() -> LinuxDoWebSession? {
        guard let data = readData(account: webSessionAccount) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(LinuxDoWebSession.self, from: data)
        } catch {
            Log.app.error("LinuxDo web session decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveWebSession(_ session: LinuxDoWebSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(session)
        try saveData(data, account: webSessionAccount)
    }

    func deleteWebSession() {
        delete(account: webSessionAccount)
    }

    private func readData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            Log.app.error("LinuxDo Keychain read failed: OSStatus \(status, privacy: .public)")
            return nil
        }
    }

    private func saveData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus)
            }
        default:
            throw KeychainError.osStatus(updateStatus)
        }
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.app.error("LinuxDo Keychain delete failed: OSStatus \(status, privacy: .public)")
        }
    }

    enum KeychainError: Error, Sendable {
        case osStatus(OSStatus)
    }
}

final class InMemoryLinuxDoCredentialStore: LinuxDoCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var webSession: LinuxDoWebSession?

    init(webSession: LinuxDoWebSession? = nil) {
        self.webSession = webSession
    }

    func deleteLegacyUserAPIKey() {}

    func readWebSession() -> LinuxDoWebSession? {
        lock.withLock { webSession }
    }

    func saveWebSession(_ session: LinuxDoWebSession) {
        lock.withLock { webSession = session }
    }

    func deleteWebSession() {
        lock.withLock { webSession = nil }
    }
}
