import Foundation
import CryptoKit

/// 沙盒应用内加密文件存储（开发期 / ad-hoc 签名下替代 Keychain）。
///
/// 设计：
///   - master key：256-bit `SymmetricKey`，首次启动随机生成，base64 存 UserDefaults
///     （UserDefaults 文件在 ~/Library/Containers/<bundle>/Data/Library/Preferences/<bundle>.plist
///      受 macOS sandbox 保护，只有本 app 能读）
///   - 内容文件：~/Library/Containers/<bundle>/Data/Library/Application Support/Tunnels/secrets.json
///   - 每条记录：account → AES-GCM 加密后的 base64
///
/// 取舍：比明文存密码安全（攻击者拿到 secrets.json 也解不开，没 master key）；
/// 比 Keychain 简单（不依赖代码签名 ACL，ad-hoc 重签 / 二进制变更不影响）。
/// 正式开发者证书签名上线后，可以切换回 Keychain。
enum SecretStore {
    private static let masterKeyDefault = "secret.masterKey.v1"
    private static let storeFileName = "secrets.json"

    private static var masterKey: SymmetricKey = loadOrCreateMasterKey()

    private static func loadOrCreateMasterKey() -> SymmetricKey {
        if let b64 = UserDefaults.standard.string(forKey: masterKeyDefault),
           let data = Data(base64Encoded: b64), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        UserDefaults.standard.set(raw.base64EncodedString(), forKey: masterKeyDefault)
        return key
    }

    private static var storeURL: URL {
        let fm = FileManager.default
        let support = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Tunnels", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(storeFileName)
    }

    private static func loadDict() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeDict(_ dict: [String: String]) throws {
        let data = try JSONEncoder().encode(dict)
        try data.write(to: storeURL, options: [.atomic])
    }

    static func save(_ secret: String, account: String) throws {
        let plain = Data(secret.utf8)
        let sealed = try AES.GCM.seal(plain, using: masterKey)
        guard let combined = sealed.combined else {
            throw SecretStoreError.encryptionFailed
        }
        var dict = loadDict()
        dict[account] = combined.base64EncodedString()
        try writeDict(dict)
    }

    static func load(account: String) -> String? {
        let dict = loadDict()
        guard let b64 = dict[account],
              let data = Data(base64Encoded: b64),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(sealedBox, using: masterKey),
              let str = String(data: plain, encoding: .utf8) else {
            return nil
        }
        return str
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        var dict = loadDict()
        let existed = dict.removeValue(forKey: account) != nil
        try? writeDict(dict)
        return existed
    }

    static func newAccountIdentifier() -> String {
        "tunnel.\(UUID().uuidString)"
    }
}

enum SecretStoreError: LocalizedError {
    case encryptionFailed
    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "加密失败"
        }
    }
}
