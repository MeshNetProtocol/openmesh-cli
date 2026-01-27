import Foundation
import Security

enum WalletStoreError: LocalizedError {
    case keychain(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .keychain(let s):
            return "Keychain 操作失败：\(s)"
        }
    }
}

struct WalletStore {
    private static let service = "com.meshflux.wallet"
    private static let accountBlob = "wallet_blob_v1" // 存 Go 返回的 JSON bytes
    
    static func hasWallet() -> Bool {
        (try? keychainGet(account: accountBlob)) != nil
    }
    
    /// ✅ 保存 Go 返回的 wallet JSON（UTF8 bytes）
    static func saveWalletBlob(_ blob: Data) throws {
        try keychainSet(account: accountBlob, data: blob)
    }
    
    static func loadWalletBlob() -> Data? {
        try? keychainGet(account: accountBlob)
    }
    
    static func clear() throws {
        try keychainDelete(account: accountBlob)
    }
    
    // MARK: - Keychain helpers
    
    private static func keychainSet(account: String, data: Data) throws {
        try? keychainDelete(account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { throw WalletStoreError.keychain(status) }
    }
    
    private static func keychainGet(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound { return nil }
        if status != errSecSuccess { throw WalletStoreError.keychain(status) }
        
        return item as? Data
    }
    
    private static func keychainDelete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw WalletStoreError.keychain(status)
        }
    }
}
