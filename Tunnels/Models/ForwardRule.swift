import Foundation
import SwiftData

@Model
final class ForwardRule {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var bindAddress: String
    var bindPort: Int
    var targetHost: String
    var targetPort: Int
    var enabled: Bool
    var note: String
    var tunnel: Tunnel?

    init(
        id: UUID = UUID(),
        kind: ForwardKind = .local,
        bindAddress: String = "127.0.0.1",
        bindPort: Int = 0,
        targetHost: String = "",
        targetPort: Int = 0,
        enabled: Bool = true,
        note: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.bindAddress = bindAddress
        self.bindPort = bindPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.enabled = enabled
        self.note = note
    }

    var kind: ForwardKind {
        get { ForwardKind(rawValue: kindRaw) ?? .local }
        set { kindRaw = newValue.rawValue }
    }

    var summary: String {
        switch kind {
        case .local:
            return "L  \(bindAddress):\(bindPort)  →  \(targetHost):\(targetPort)"
        case .remote:
            return "R  远程:\(bindPort)  →  \(targetHost):\(targetPort)"
        case .dynamic:
            return "D  SOCKS \(bindAddress):\(bindPort)"
        }
    }

    var isValid: Bool {
        guard bindPort > 0 && bindPort <= 65535 else { return false }
        switch kind {
        case .local, .remote:
            return !targetHost.isEmpty && targetPort > 0 && targetPort <= 65535
        case .dynamic:
            return true
        }
    }
}
