import Foundation

/// SwiftData ``Tunnel`` 在引擎中需要跨 actor 使用，
/// 因此抽出一个 Sendable 值类型快照。
struct TunnelSnapshot: Sendable, Hashable {
    let id: UUID
    let name: String
    let host: String
    let port: Int
    let username: String
    let backend: TunnelBackend
    let authMethod: AuthMethod
    let privateKeyPath: String?
    let keychainAccount: String?
    let privateKeyMaterialAccount: String?
    let keepAliveInterval: Int
    let compression: Bool
    let rules: [ForwardRuleSnapshot]
}

struct ForwardRuleSnapshot: Sendable, Hashable {
    let id: UUID
    let kind: ForwardKind
    let bindAddress: String
    let bindPort: Int
    let targetHost: String
    let targetPort: Int
    let enabled: Bool
}

extension TunnelSnapshot {
    @MainActor
    init(from tunnel: Tunnel) {
        self.id = tunnel.id
        self.name = tunnel.name
        self.host = tunnel.host
        self.port = tunnel.port
        self.username = tunnel.username
        self.backend = tunnel.backend
        self.authMethod = tunnel.authMethod
        self.privateKeyPath = tunnel.privateKeyPath
        self.keychainAccount = tunnel.keychainAccount
        self.privateKeyMaterialAccount = tunnel.privateKeyMaterialAccount
        self.keepAliveInterval = tunnel.keepAliveInterval
        self.compression = tunnel.compression
        self.rules = tunnel.rules.map { ForwardRuleSnapshot(from: $0) }
    }
}

extension ForwardRuleSnapshot {
    @MainActor
    init(from rule: ForwardRule) {
        self.id = rule.id
        self.kind = rule.kind
        self.bindAddress = rule.bindAddress
        self.bindPort = rule.bindPort
        self.targetHost = rule.targetHost
        self.targetPort = rule.targetPort
        self.enabled = rule.enabled
    }
}
