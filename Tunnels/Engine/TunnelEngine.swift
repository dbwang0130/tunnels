import Foundation

enum TunnelStatus: Equatable, Hashable {
    case idle
    case connecting
    case connected
    case reconnecting
    case stopping
    case stopped
    case failed(String)

    var isActive: Bool {
        switch self {
        case .connecting, .connected, .reconnecting: return true
        default: return false
        }
    }

    var displayText: String {
        switch self {
        case .idle: return "未启动"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .reconnecting: return "重连中"
        case .stopping: return "停止中"
        case .stopped: return "已停止"
        case .failed(let msg): return "失败: \(msg)"
        }
    }
}

struct LogLine: Identifiable, Hashable {
    enum Level: String { case info, warn, error, debug }
    let id = UUID()
    let timestamp: Date
    let level: Level
    let message: String
}

protocol TunnelEngine: AnyObject {
    var tunnelID: UUID { get }
    var status: TunnelStatus { get }
    func start() async
    func stop() async
    func setHandlers(
        onStatus: @escaping @Sendable (TunnelStatus) -> Void,
        onLog: @escaping @Sendable (LogLine) -> Void
    )
}
