import Foundation

/// 兼容 API：保留 `Keychain` 命名空间，内部委托给 ``SecretStore``
/// 沙盒内加密文件存储（开发期 / ad-hoc 签名下不会弹密码框）。
enum Keychain {
    static func save(_ secret: String, account: String) throws {
        try SecretStore.save(secret, account: account)
    }

    static func load(account: String) throws -> String? {
        SecretStore.load(account: account)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        SecretStore.delete(account: account)
    }

    static func newAccountIdentifier() -> String {
        SecretStore.newAccountIdentifier()
    }
}
