import Foundation
import Observation
import SwiftUI

#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let tunnelsResumeAfterWake = Notification.Name("tunnelsResumeAfterWake")
}

@Observable
@MainActor
final class TunnelManager {
    static let shared = TunnelManager()

    /// 睡眠前记录的活跃隧道 ID；唤醒后通过 NotificationCenter 让上层把它们再起来。
    private var sleepActiveIDs: [UUID] = []

    private(set) var statuses: [UUID: TunnelStatus] = [:]
    private(set) var logs: [UUID: [LogLine]] = [:]

    private var engines: [UUID: TunnelEngine] = [:]
    private let logCap = 500

    private struct StartContext {
        let snapshot: TunnelSnapshot
        let secret: String?
        let privateKeyMaterial: String?
        let autoReconnect: Bool
    }
    private var startContexts: [UUID: StartContext] = [:]
    private var reconnectAttempts: [UUID: Int] = [:]
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]
    private let reconnectMaxDelay = 300

    init() {
#if os(macOS)
        observeSleepWake()
#endif
    }

#if os(macOS)
    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleWillSleep() }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleDidWake() }
        }
    }

    private func handleWillSleep() {
        let active = activeIDs
        guard !active.isEmpty else { return }
        sleepActiveIDs = active
        for id in active { stop(id: id) }
    }

    private func handleDidWake() {
        let toResume = sleepActiveIDs
        sleepActiveIDs.removeAll()
        guard !toResume.isEmpty else { return }
        NotificationCenter.default.post(
            name: .tunnelsResumeAfterWake,
            object: nil,
            userInfo: ["ids": toResume]
        )
    }
#endif

    func status(of id: UUID) -> TunnelStatus {
        statuses[id] ?? .idle
    }

    func logs(of id: UUID) -> [LogLine] {
        logs[id] ?? []
    }

    func isRunning(_ id: UUID) -> Bool {
        status(of: id).isActive
    }

    func start(_ tunnel: Tunnel) {
        let id = tunnel.id
        if engines[id] != nil { return }

        let snapshot = TunnelSnapshot(from: tunnel)
        let secret: String? = {
            guard let account = tunnel.keychainAccount else { return nil }
            return (try? Keychain.load(account: account)) ?? nil
        }()
        let privateKeyMaterial: String? = {
            guard let account = tunnel.privateKeyMaterialAccount else { return nil }
            return (try? Keychain.load(account: account)) ?? nil
        }()

        // 诊断：配置了认证但读不到 Keychain 内容 —— 多半是 Keychain 实现升级造成的旧记录失效
        if snapshot.backend == .ssh {
            if snapshot.authMethod == .privateKey,
               snapshot.privateKeyMaterialAccount != nil, privateKeyMaterial == nil {
                appendLog(id: id, line: LogLine(
                    timestamp: Date(), level: .warn,
                    message: "Keychain 未能读到私钥（可能因实现升级失效）。请编辑该隧道 → 重新「选择私钥…」并保存。"
                ))
            }
            if snapshot.authMethod == .password,
               snapshot.keychainAccount != nil, secret == nil {
                appendLog(id: id, line: LogLine(
                    timestamp: Date(), level: .warn,
                    message: "Keychain 未能读到密码（可能因实现升级失效）。请编辑该隧道 → 重新输入密码并保存。"
                ))
            }
        }

        let context = StartContext(
            snapshot: snapshot,
            secret: secret,
            privateKeyMaterial: privateKeyMaterial,
            autoReconnect: tunnel.autoReconnect
        )
        startContexts[id] = context
        reconnectAttempts[id] = 0
        reconnectTasks[id]?.cancel()
        reconnectTasks.removeValue(forKey: id)

        launchEngine(id: id, context: context)
    }

    private func launchEngine(id: UUID, context: StartContext) {
        let engine: TunnelEngine
        switch context.snapshot.backend {
        case .ssh:
            engine = SSHEngine(
                snapshot: context.snapshot,
                secret: context.secret,
                privateKeyMaterial: context.privateKeyMaterial
            )
        case .plainTCP:
            engine = TCPForwardEngine(snapshot: context.snapshot)
        }

        engine.setHandlers(
            onStatus: { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.applyStatus(id: id, status: status)
                }
            },
            onLog: { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.appendLog(id: id, line: line)
                }
            }
        )

        engines[id] = engine
        statuses[id] = .connecting
        if logs[id] == nil { logs[id] = [] }

        Task { await engine.start() }
    }

    func stop(_ tunnel: Tunnel) {
        stop(id: tunnel.id)
    }

    func stop(id: UUID) {
        // 用户主动停止：取消任何排队中的重连并清理 context
        reconnectTasks[id]?.cancel()
        reconnectTasks.removeValue(forKey: id)
        startContexts.removeValue(forKey: id)
        reconnectAttempts.removeValue(forKey: id)
        guard let engine = engines[id] else { return }
        statuses[id] = .stopping
        Task { [weak self] in
            await engine.stop()
            _ = await MainActor.run { [weak self] in
                self?.engines.removeValue(forKey: id)
            }
        }
    }

    func toggle(_ tunnel: Tunnel) {
        if isRunning(tunnel.id) {
            stop(tunnel)
        } else {
            start(tunnel)
        }
    }

    /// 用户在已运行的隧道上改了规则后调一下，会停下当前连接、用最新 snapshot 重启。
    /// 隧道未在运行时不做任何事。
    func reapplyRules(of tunnel: Tunnel) {
        let id = tunnel.id
        guard engines[id] != nil else { return }
        appendLog(id: id, line: LogLine(
            timestamp: Date(), level: .info,
            message: "规则已变更，重新应用…"
        ))
        reconnectTasks[id]?.cancel()
        reconnectTasks.removeValue(forKey: id)
        let engine = engines[id]
        statuses[id] = .stopping
        Task { [weak self, tunnel] in
            await engine?.stop()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.engines.removeValue(forKey: id)
                self.start(tunnel)
            }
        }
    }

    func clearLogs(of id: UUID) {
        logs[id] = []
    }

    var activeIDs: [UUID] {
        statuses.compactMap { $0.value.isActive ? $0.key : nil }
    }

    // 状态合并：终态立即发布；过渡态延迟 80ms 合并，避免短暂中间态触发 UI 重渲染。
    private var pendingStatus: [UUID: TunnelStatus] = [:]
    private var statusCommitTask: Task<Void, Never>?

    private func applyStatus(id: UUID, status: TunnelStatus) {
        if isTerminal(status) {
            // 立即提交（含 pending 中可能堆积的）
            statusCommitTask?.cancel()
            statusCommitTask = nil
            pendingStatus[id] = status
            commitPendingStatuses()
        } else {
            pendingStatus[id] = status
            if statusCommitTask == nil {
                statusCommitTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled, let self else { return }
                    self.statusCommitTask = nil
                    self.commitPendingStatuses()
                }
            }
        }
    }

    private func commitPendingStatuses() {
        for (id, s) in pendingStatus {
            statuses[id] = s
            if case .connected = s { reconnectAttempts[id] = 0 }
            if case .stopped = s { engines.removeValue(forKey: id) }
            if case .failed = s {
                engines.removeValue(forKey: id)
                scheduleReconnectIfNeeded(id: id)
            }
        }
        pendingStatus.removeAll()
    }

    private func scheduleReconnectIfNeeded(id: UUID) {
        guard let context = startContexts[id], context.autoReconnect else { return }
        if reconnectTasks[id] != nil { return }
        let attempt = (reconnectAttempts[id] ?? 0) + 1
        reconnectAttempts[id] = attempt
        let base = max(1, AppPreferences.shared.reconnectBackoff)
        let capped = min(reconnectMaxDelay, base * Int(pow(2.0, Double(min(attempt - 1, 8)))))
        appendLog(id: id, line: LogLine(
            timestamp: Date(), level: .info,
            message: "\(capped)s 后自动重连（第 \(attempt) 次）"
        ))
        statuses[id] = .reconnecting
        let delay = capped
        reconnectTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            self.reconnectTasks.removeValue(forKey: id)
            if Task.isCancelled { return }
            guard let ctx = self.startContexts[id] else { return }
            if self.engines[id] != nil { return }
            self.launchEngine(id: id, context: ctx)
        }
    }

    private func isTerminal(_ s: TunnelStatus) -> Bool {
        switch s {
        case .connected, .failed, .stopped: return true
        default: return false
        }
    }

    private func appendLog(id: UUID, line: LogLine) {
        var current = logs[id] ?? []
        // 节流：与上一条同级别 + 同消息（去除已有 "×N" 后缀）且 500ms 内 → 合并
        if let last = current.last,
           last.level == line.level,
           line.timestamp.timeIntervalSince(last.timestamp) < 0.5,
           coreMessage(last.message) == line.message {
            let count = repeatCount(of: last.message) + 1
            current.removeLast()
            current.append(LogLine(
                timestamp: line.timestamp,
                level: line.level,
                message: "\(line.message)  ×\(count)"
            ))
        } else {
            current.append(line)
        }
        if current.count > logCap {
            current.removeFirst(current.count - logCap)
        }
        logs[id] = current
    }

    private func coreMessage(_ s: String) -> String {
        if let range = s.range(of: #"\s+×\d+$"#, options: .regularExpression) {
            return String(s[..<range.lowerBound])
        }
        return s
    }

    private func repeatCount(of s: String) -> Int {
        if let r = s.range(of: #"×(\d+)$"#, options: .regularExpression) {
            return Int(s[r].dropFirst()) ?? 1
        }
        return 1
    }
}

extension TunnelStatus {
    var color: Color {
        switch self {
        case .idle, .stopped: return .secondary
        case .connecting, .reconnecting, .stopping: return .orange
        case .connected: return .green
        case .failed: return .red
        }
    }

    var symbolName: String {
        switch self {
        case .idle, .stopped: return "circle"
        case .connecting, .reconnecting, .stopping: return "circle.dotted"
        case .connected: return "circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
