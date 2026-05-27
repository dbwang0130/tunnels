import Foundation
import SwiftData

@Model
final class Tunnel {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethodRaw: String
    var backendRaw: String
    var privateKeyPath: String?
    var keychainAccount: String?
    var privateKeyMaterialAccount: String?
    var autoStart: Bool
    var autoReconnect: Bool
    var keepAliveInterval: Int
    var compression: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ForwardRule.tunnel)
    var rules: [ForwardRule]

    init(
        id: UUID = UUID(),
        name: String = "新建隧道",
        host: String = "",
        port: Int = 22,
        username: String = "",
        authMethod: AuthMethod = .password,
        backend: TunnelBackend = .ssh,
        privateKeyPath: String? = nil,
        keychainAccount: String? = nil,
        privateKeyMaterialAccount: String? = nil,
        autoStart: Bool = false,
        autoReconnect: Bool = true,
        keepAliveInterval: Int = 30,
        compression: Bool = false,
        note: String = "",
        rules: [ForwardRule] = []
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethodRaw = authMethod.rawValue
        self.backendRaw = backend.rawValue
        self.privateKeyPath = privateKeyPath
        self.keychainAccount = keychainAccount
        self.privateKeyMaterialAccount = privateKeyMaterialAccount
        self.autoStart = autoStart
        self.autoReconnect = autoReconnect
        self.keepAliveInterval = keepAliveInterval
        self.compression = compression
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
        self.rules = rules
    }

    var authMethod: AuthMethod {
        get { AuthMethod(rawValue: authMethodRaw) ?? .password }
        set { authMethodRaw = newValue.rawValue }
    }

    var backend: TunnelBackend {
        get { TunnelBackend(rawValue: backendRaw) ?? .ssh }
        set { backendRaw = newValue.rawValue }
    }

    var displayDestination: String {
        let user = username.isEmpty ? "" : "\(username)@"
        return "\(user)\(host):\(port)"
    }

    var enabledRules: [ForwardRule] {
        rules.filter { $0.enabled }.sorted { $0.bindPort < $1.bindPort }
    }
}
