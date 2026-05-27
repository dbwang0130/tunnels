import Foundation

enum ForwardKind: String, Codable, CaseIterable, Identifiable {
    case local
    case remote
    case dynamic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地转发 (-L)"
        case .remote: return "远程转发 (-R)"
        case .dynamic: return "动态 SOCKS (-D)"
        }
    }

    var symbolName: String {
        switch self {
        case .local: return "arrow.left.arrow.right"
        case .remote: return "arrow.up.arrow.down"
        case .dynamic: return "globe"
        }
    }
}

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey
    case agent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password: return "密码"
        case .privateKey: return "私钥"
        case .agent: return "SSH Agent"
        }
    }
}

enum TunnelBackend: String, Codable, CaseIterable, Identifiable {
    case ssh
    case plainTCP

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ssh: return "SSH 隧道"
        case .plainTCP: return "明文 TCP 转发"
        }
    }

    var detail: String {
        switch self {
        case .ssh: return "通过 SSH 服务器加密转发（需配置 SSH 后端）"
        case .plainTCP: return "直接 TCP 端口映射，仅支持本地转发，不加密"
        }
    }
}
