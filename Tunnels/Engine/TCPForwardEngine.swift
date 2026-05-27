import Foundation
import Network

actor TCPForwardEngine: TunnelEngine {
    nonisolated let tunnelID: UUID
    private let snapshot: TunnelSnapshot

    nonisolated var status: TunnelStatus {
        statusBox.value
    }
    private let statusBox = StatusBox()

    private var listeners: [NWListener] = []
    private var bridges: [ObjectIdentifier: Bridge] = [:]

    private var onStatus: (@Sendable (TunnelStatus) -> Void)?
    private var onLog: (@Sendable (LogLine) -> Void)?

    init(snapshot: TunnelSnapshot) {
        self.tunnelID = snapshot.id
        self.snapshot = snapshot
    }

    nonisolated func setHandlers(
        onStatus: @escaping @Sendable (TunnelStatus) -> Void,
        onLog: @escaping @Sendable (LogLine) -> Void
    ) {
        Task { await self._setHandlers(onStatus: onStatus, onLog: onLog) }
    }

    private func _setHandlers(
        onStatus: @escaping @Sendable (TunnelStatus) -> Void,
        onLog: @escaping @Sendable (LogLine) -> Void
    ) {
        self.onStatus = onStatus
        self.onLog = onLog
    }

    func start() async {
        await transition(.connecting)
        log(.info, "启动 TCP 转发引擎（无加密）")

        var bound = 0
        for rule in snapshot.rules where rule.enabled && rule.kind == .local {
            do {
                try await openListener(for: rule)
                bound += 1
            } catch {
                log(.error, "本地端口 \(rule.bindPort) 绑定失败: \(error.localizedDescription)")
            }
        }

        if bound == 0 {
            await transition(.failed("没有可用的本地转发规则"))
            return
        }
        await transition(.connected)
        log(.info, "已绑定 \(bound) 条本地转发规则")
    }

    func stop() async {
        await transition(.stopping)
        for listener in listeners {
            listener.cancel()
        }
        listeners.removeAll()
        for bridge in bridges.values {
            bridge.cancel()
        }
        bridges.removeAll()
        await transition(.stopped)
        log(.info, "已停止")
    }

    private func openListener(for rule: ForwardRuleSnapshot) async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .other
        guard let port = NWEndpoint.Port(rawValue: UInt16(rule.bindPort)) else {
            throw NSError(domain: "Tunnels", code: 1, userInfo: [NSLocalizedDescriptionKey: "端口非法"])
        }
        let listener = try NWListener(using: params, on: port)

        listener.newConnectionHandler = { [weak self] incoming in
            guard let self else { return }
            Task { await self.acceptIncoming(incoming, rule: rule) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleListenerState(state, rule: rule) }
        }
        listener.start(queue: .global(qos: .userInitiated))
        listeners.append(listener)
        log(.info, "监听 \(rule.bindAddress):\(rule.bindPort) → \(rule.targetHost):\(rule.targetPort)")
    }

    private func handleListenerState(_ state: NWListener.State, rule: ForwardRuleSnapshot) async {
        switch state {
        case .failed(let err):
            log(.error, "监听器失败 (端口 \(rule.bindPort)): \(err.localizedDescription)")
        case .ready:
            log(.debug, "监听器就绪 (端口 \(rule.bindPort))")
        default: break
        }
    }

    private func acceptIncoming(_ incoming: NWConnection, rule: ForwardRuleSnapshot) async {
        let target = NWEndpoint.hostPort(
            host: NWEndpoint.Host(rule.targetHost),
            port: NWEndpoint.Port(rawValue: UInt16(rule.targetPort)) ?? 0
        )
        let upstream = NWConnection(to: target, using: .tcp)
        let bridge = Bridge(downstream: incoming, upstream: upstream) { [weak self] line in
            Task { await self?.appendLog(line) }
        } onClose: { [weak self] bridgeID in
            Task { await self?.removeBridge(bridgeID) }
        }
        let key = ObjectIdentifier(bridge)
        bridges[key] = bridge
        bridge.start()
    }

    private func removeBridge(_ id: ObjectIdentifier) {
        bridges.removeValue(forKey: id)
    }

    private func appendLog(_ line: LogLine) {
        onLog?(line)
    }

    private func transition(_ next: TunnelStatus) async {
        statusBox.value = next
        onStatus?(next)
    }

    private func log(_ level: LogLine.Level, _ msg: String) {
        let line = LogLine(timestamp: Date(), level: level, message: msg)
        onLog?(line)
    }
}

private final class StatusBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var stored: TunnelStatus = .idle

    nonisolated init() {}

    nonisolated var value: TunnelStatus {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

private final class Bridge: @unchecked Sendable {
    nonisolated let downstream: NWConnection
    nonisolated let upstream: NWConnection
    nonisolated private let onLog: @Sendable (LogLine) -> Void
    nonisolated private let onClose: @Sendable (ObjectIdentifier) -> Void
    nonisolated(unsafe) private var closed = false
    nonisolated private let lock = NSLock()

    nonisolated init(
        downstream: NWConnection,
        upstream: NWConnection,
        onLog: @escaping @Sendable (LogLine) -> Void,
        onClose: @escaping @Sendable (ObjectIdentifier) -> Void
    ) {
        self.downstream = downstream
        self.upstream = upstream
        self.onLog = onLog
        self.onClose = onClose
    }

    nonisolated func start() {
        upstream.start(queue: .global(qos: .userInitiated))
        downstream.start(queue: .global(qos: .userInitiated))
        pipe(from: downstream, to: upstream)
        pipe(from: upstream, to: downstream)
    }

    /// 流水线模式：receive 不等待 send 完成即触发下一次 receive，
    /// 让源端读取与目的端写入并行；NWConnection 内部 send 队列提供天然背压。
    nonisolated private func pipe(from src: NWConnection, to dst: NWConnection) {
        src.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.onLog(.init(timestamp: Date(), level: .warn, message: "转发读取失败: \(error)"))
                self.cancel()
                return
            }
            if let data, !data.isEmpty {
                dst.send(content: data, completion: .contentProcessed { [weak self] sendErr in
                    if let sendErr {
                        self?.onLog(.init(timestamp: Date(), level: .warn, message: "转发写入失败: \(sendErr)"))
                        self?.cancel()
                    }
                })
            }
            if isComplete {
                self.cancel()
            } else {
                self.pipe(from: src, to: dst)
            }
        }
    }

    nonisolated func cancel() {
        lock.lock()
        let already = closed
        closed = true
        lock.unlock()
        if already { return }
        downstream.cancel()
        upstream.cancel()
        onClose(ObjectIdentifier(self))
    }
}
