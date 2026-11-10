import Foundation
import OmanCore
import Security

enum KeychainStoreError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)
    case unreadableItem

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let detail = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "Unknown error"
            return "Keychain error \(status): \(detail)"
        case .unreadableItem:
            return "The API key stored in Keychain could not be read."
        }
    }
}

public struct KeychainAPIKeyStore: APIKeyStore {
    private let service: String
    private let account: String

    public init() {
        self.init(service: "com.romanbitca.oman", account: "anthropic-api-key")
    }

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func loadAPIKey() throws -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainStoreError.unreadableItem
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    public func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(itemQuery as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = itemQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }
    }

    public func deleteAPIKey() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}
