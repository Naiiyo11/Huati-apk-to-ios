import Foundation
import CryptoKit
import Security

final class SecureStore {
    private let folder: URL
    private let key: SymmetricKey
    private static let service = "cn.huati.assistant.ios.storage"

    init() throws {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        folder = root.appendingPathComponent("Huati", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var folderURL = folder
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        try folderURL.setResourceValues(excluded)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: "state-key", kSecReturnData as String: true]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let bytes = item as? Data, bytes.count == 32 {
            key = SymmetricKey(data: bytes)
        } else if status == errSecItemNotFound {
            // A missing key must not silently replace the key for existing encrypted records.
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            guard !files.contains(where: { $0.pathExtension == "sealed" }) else { throw AppError("加密密钥不可用，原记录已保留，请恢复原设备钥匙串") }
            var bytes = Data(count: 32)
            let randomStatus = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            guard randomStatus == errSecSuccess else { throw AppError("无法建立加密存储") }
            let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: "state-key", kSecValueData as String: bytes, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw AppError("无法保存加密密钥") }
            key = SymmetricKey(data: bytes)
        } else { throw AppError("加密存储暂不可用，请先解锁手机") }
    }

    private func url(_ name: String) -> URL { folder.appendingPathComponent(name).appendingPathExtension("sealed") }
    func read(_ name: String) throws -> JSON? {
        let source = url(name)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: source))
        let clear = try AES.GCM.open(box, using: key, authenticating: Data(name.utf8))
        guard let value = try JSONSerialization.jsonObject(with: clear) as? JSON else { throw AppError("本地数据格式损坏，已保留原文件") }
        return value
    }
    func write(_ name: String, _ value: JSON) throws {
        let clear = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let sealed = try AES.GCM.seal(clear, using: key, authenticating: Data(name.utf8))
        guard let combined = sealed.combined else { throw AppError("本地加密失败") }
        try combined.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func remove(_ name: String) throws {
        if FileManager.default.fileExists(atPath: url(name).path) { try FileManager.default.removeItem(at: url(name)) }
    }
}
