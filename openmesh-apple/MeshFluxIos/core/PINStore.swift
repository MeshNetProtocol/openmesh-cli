//
//  PINStore.swift
//  MeshFlux
//
//  Minimal PIN storage: Keychain stores salt + SHA256(PIN + salt)
//  iOS 15+
//

import Foundation
import CryptoKit
import Security

enum PINStoreError: LocalizedError {
    case invalidPIN
    case keychain(OSStatus)
    case missingMaterial
    
    var errorDescription: String? {
        switch self {
        case .invalidPIN:
            return "PIN 必须是 6 位数字"
        case .keychain(let status):
            return "Keychain 操作失败：\(status)"
        case .missingMaterial:
            return "未找到已保存的 PIN 校验材料"
        }
    }
}

struct PINStore {
    private static let service = "com.meshflux.pin"
    private static let accountSalt = "pin_salt"
    private static let accountHash = "pin_hash"
    
    static func hasPIN() -> Bool {
        (try? keychainGet(account: accountSalt)) != nil &&
        (try? keychainGet(account: accountHash)) != nil
    }
    
    static func savePIN(_ pin: String) throws {
        guard isValid(pin) else { throw PINStoreError.invalidPIN }
        
        let salt = try randomData(count: 16)
        let hash = sha256(pin: pin, salt: salt)
        
        try keychainSet(account: accountSalt, data: salt)
        try keychainSet(account: accountHash, data: hash)
    }
    
    static func verify(_ pin: String) -> Bool {
        guard isValid(pin) else { return false }
        guard
            let salt = try? keychainGet(account: accountSalt),
            let saved = try? keychainGet(account: accountHash)
        else { return false }
        
        return sha256(pin: pin, salt: salt) == saved
    }
    
    static func clear() throws {
        try keychainDelete(account: accountSalt)
        try keychainDelete(account: accountHash)
    }
    
    // MARK: - Internal
    
    private static func isValid(_ pin: String) -> Bool {
        pin.count == 6 && pin.allSatisfy { $0.isNumber }
    }
    
    private static func sha256(pin: String, salt: Data) -> Data {
        let pinData = Data(pin.utf8)
        let digest = SHA256.hash(data: pinData + salt)
        return Data(digest)
    }
    
    private static func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        if result != errSecSuccess {
            throw PINStoreError.keychain(result)
        }
        return data
    }
    
    // MARK: - Keychain helpers
    
    private static func keychainSet(account: String, data: Data) throws {
        // upsert: delete then add
        try? keychainDelete(account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw PINStoreError.keychain(status)
        }
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
        if status != errSecSuccess { throw PINStoreError.keychain(status) }
        
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
            throw PINStoreError.keychain(status)
        }
    }
}

private extension Data {
    static func + (lhs: Data, rhs: Data) -> Data {
        var d = Data()
        d.append(lhs)
        d.append(rhs)
        return d
    }
}
