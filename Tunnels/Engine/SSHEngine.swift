import Foundation
import Network

#if canImport(Citadel)
import Citadel
import NIOCore
import NIOPosix
import NIOSSH
import Crypto

/// 基于 Citadel (https://github.com/orlandos-nl/Citadel) 的 SSH 隧道引擎。
///
/// 集成步骤：
/// 1. Xcode → File → Add Package Dependencies…
///       https://github.com/orlandos-nl/Citadel.git，Up to Next Minor 0.12.1
/// 2. 把 Citadel 产品 link 到 Tunnels target。
/// 3. 重新编译 —— 本文件 ``#if canImport(Citadel)`` 分支会自动启用。
///
/// 已支持：
///   - 本地转发 (-L)
///   - 远程转发 (-R) —— 注意 Citadel 单连接同一时间只允许一个 remote forward handler，
///     多条 .remote 规则会取首条生效
///   - 密码 / ed25519 / RSA 私钥认证
///
/// 暂未支持：动态转发 SOCKS5、SSH Agent 转发、known_hosts 验证（默认 acceptAnything）。
actor SSHEngine: TunnelEngine {
    nonisolated let tunnelID: UUID
    private let snapshot: TunnelSnapshot
    private let secret: String?
    private let privateKeyMaterial: String?

    nonisolated var status: TunnelStatus { statusBox.value }
    private let statusBox = SSHStatusBox()

    private var onStatus: (@Sendable (TunnelStatus) -> Void)?
    private var onLog: (@Sendable (LogLine) -> Void)?

    private var client: SSHClient?
    private var listeners: [NWListener] = []
    private var sideTasks: [Task<Void, Never>] = []
    private var stopRequested = false
    private var keepAliveTask: Task<Void, Never>?
    private var keepAliveFailures = 0
    private static let keepAliveFailureLimit = 3

    init(snapshot: TunnelSnapshot, secret: String?, privateKeyMaterial: String? = nil) {
        self.tunnelID = snapshot.id
        self.snapshot = snapshot
        self.secret = secret
        self.privateKeyMaterial = privateKeyMaterial
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
        stopRequested = false
        transition(.connecting)
        log(.info, "正在连接 \(snapshot.username)@\(snapshot.host):\(snapshot.port)")

        do {
            let auth = try buildAuthentication()
            let settings = SSHClientSettings(
                host: snapshot.host,
                port: snapshot.port,
                authenticationMethod: { auth },
                hostKeyValidator: .acceptAnything()
            )
            let connected = try await SSHClient.connect(to: settings)
            self.client = connected
            log(.info, "SSH 握手完成")
            transition(.connected)
            installDisconnectWatcher(on: connected)
        } catch {
            log(.error, "连接失败: \(error)")
            transition(.failed("\(error)"))
            return
        }

        var localCount = 0, remoteCount = 0, dynamicSkipped = 0
        for rule in snapshot.rules where rule.enabled {
            switch rule.kind {
            case .local:
                do {
                    try await openLocalForward(rule)
                    localCount += 1
                } catch {
                    log(.error, "本地转发 :\(rule.bindPort) 启动失败: \(error)")
                }
            case .remote:
                if remoteCount > 0 {
                    log(.warn, "Citadel 限制单连接仅支持一个 remote forward，跳过额外的 -R \(rule.bindPort)")
                    continue
                }
                startRemoteForward(rule)
                remoteCount += 1
            case .dynamic:
                dynamicSkipped += 1
            }
        }

        if dynamicSkipped > 0 {
            log(.warn, "动态 SOCKS 转发尚未实现，已跳过 \(dynamicSkipped) 条")
        }
        log(.info, "已激活规则：本地 \(localCount)，远程 \(remoteCount)")

        startKeepAlive()
    }

    func stop() async {
        stopRequested = true
        transition(.stopping)
        keepAliveTask?.cancel()
        keepAliveTask = nil
        for listener in listeners { listener.cancel() }
        listeners.removeAll()
        for task in sideTasks { task.cancel() }
        sideTasks.removeAll()
        if let client {
            try? await client.close()
        }
        client = nil
        transition(.stopped)
        log(.info, "已停止")
    }

    // MARK: - 保活

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveFailures = 0
        let interval = snapshot.keepAliveInterval
        guard interval > 0 else { return }
        let seconds = UInt64(max(5, interval))
        log(.debug, "启用保活，每 \(seconds)s ping 一次")
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                } catch { return }
                if Task.isCancelled { return }
                await self?.pingOnce()
            }
        }
    }

    private func pingOnce() async {
        guard !stopRequested else { return }
        guard let client else { return }
        if !client.isConnected {
            await handleConnectionLost(reason: "底层 TCP 已不活跃")
            return
        }
        do {
            _ = try await client.executeCommand("true")
            if keepAliveFailures > 0 {
                log(.info, "保活恢复正常")
            } else {
                log(.debug, "保活 ping ok")
            }
            keepAliveFailures = 0
        } catch {
            keepAliveFailures += 1
            log(.warn, "保活 ping 失败 (#\(keepAliveFailures)/\(Self.keepAliveFailureLimit))：\(error)")
            if keepAliveFailures >= Self.keepAliveFailureLimit {
                await handleConnectionLost(reason: "连续 \(Self.keepAliveFailureLimit) 次保活失败")
            }
        }
    }

    private func installDisconnectWatcher(on client: SSHClient) {
        client.onDisconnect { [weak self] in
            Task { await self?.handleConnectionLost(reason: "对端断开") }
        }
    }

    private func handleConnectionLost(reason: String) async {
        guard !stopRequested, client != nil else { return }
        log(.error, "连接丢失：\(reason)")
        keepAliveTask?.cancel()
        keepAliveTask = nil
        for listener in listeners { listener.cancel() }
        listeners.removeAll()
        for task in sideTasks { task.cancel() }
        sideTasks.removeAll()
        if let c = client { try? await c.close() }
        client = nil
        transition(.failed(reason))
    }

    // MARK: - 认证

    private func buildAuthentication() throws -> SSHAuthenticationMethod {
        switch snapshot.authMethod {
        case .password:
            return .passwordBased(username: snapshot.username, password: secret ?? "")
        case .privateKey:
            guard let pem = privateKeyMaterial, !pem.isEmpty else {
                throw SSHEngineError.missingPrivateKey
            }
            let passphrase = secret.flatMap { $0.data(using: .utf8) }
            // 优先尝试 ed25519，失败再 RSA
            if let key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: passphrase) {
                return .ed25519(username: snapshot.username, privateKey: key)
            }
            if let key = try? Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: passphrase) {
                return .rsa(username: snapshot.username, privateKey: key)
            }
            throw SSHEngineError.invalidPrivateKey
        case .agent:
            throw SSHEngineError.agentUnsupported
        }
    }

    // MARK: - 本地转发 (-L)

    private func openLocalForward(_ rule: ForwardRuleSnapshot) async throws {
        guard let client else { throw SSHEngineError.notConnected }
        guard let port = NWEndpoint.Port(rawValue: UInt16(rule.bindPort)) else {
            throw SSHEngineError.invalidPort
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: port)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.log(state == .ready ? .debug : .info, "监听 :\(rule.bindPort) → \(state)") }
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { await self.bridgeLocalToSSH(conn, rule: rule, client: client) }
        }
        listener.start(queue: .global(qos: .userInitiated))
        listeners.append(listener)
        log(.info, "L \(rule.bindAddress):\(rule.bindPort) → \(rule.targetHost):\(rule.targetPort)")
    }

    private func bridgeLocalToSSH(_ inbound: NWConnection, rule: ForwardRuleSnapshot, client: SSHClient) async {
        do {
            let originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
            let bridge = LocalBridge(inbound: inbound) { [weak self] line in
                Task { await self?.appendLog(line) }
            }
            let sshChannel = try await client.createDirectTCPIPChannel(
                using: SSHChannelType.DirectTCPIP(
                    targetHost: rule.targetHost,
                    targetPort: rule.targetPort,
                    originatorAddress: originator
                )
            ) { sshChannel in
                sshChannel.pipeline.addHandler(NWBridgeHandler(bridge: bridge))
            }
            bridge.attach(sshChannel: sshChannel)
        } catch {
            log(.warn, "本地→SSH 通道建立失败: \(error)")
            inbound.cancel()
        }
    }

    // MARK: - 远程转发 (-R)

    private func startRemoteForward(_ rule: ForwardRuleSnapshot) {
        let task = Task { [weak self] in
            guard let self, let client = await self.client else { return }
            do {
                try await client.withRemotePortForward(
                    host: rule.bindAddress.isEmpty ? "0.0.0.0" : rule.bindAddress,
                    port: rule.bindPort,
                    onOpen: { [weak self] info in
                        await self?.log(.info, "R 远程 :\(info.boundPort) → \(rule.targetHost):\(rule.targetPort)")
                    },
                    handleChannel: { [rule] sshChannel, _ in
                        Self.bridgeRemoteToLocal(sshChannel: sshChannel, rule: rule)
                    }
                )
            } catch {
                if !Task.isCancelled {
                    await self.log(.error, "远程转发失败: \(error)")
                }
            }
        }
        sideTasks.append(task)
    }

    nonisolated private static func bridgeRemoteToLocal(sshChannel: Channel, rule: ForwardRuleSnapshot) -> EventLoopFuture<Void> {
        let eventLoop = sshChannel.eventLoop
        return ClientBootstrap(group: eventLoop)
            .connect(host: rule.targetHost, port: rule.targetPort)
            .flatMap { localChannel in
                let glue1 = NIOGlue(target: localChannel)
                let glue2 = NIOGlue(target: sshChannel)
                return sshChannel.pipeline.addHandler(glue1).flatMap {
                    localChannel.pipeline.addHandler(glue2)
                }
            }
    }

    // MARK: - 工具

    private func appendLog(_ line: LogLine) { onLog?(line) }

    private func transition(_ next: TunnelStatus) {
        statusBox.value = next
        onStatus?(next)
    }

    private func log(_ level: LogLine.Level, _ msg: String) {
        onLog?(LogLine(timestamp: Date(), level: level, message: msg))
    }
}

// MARK: - 错误

private enum SSHEngineError: LocalizedError {
    case notConnected, invalidPort, missingPrivateKey, invalidPrivateKey, agentUnsupported

    var errorDescription: String? {
        switch self {
        case .notConnected: return "SSH 客户端未连接"
        case .invalidPort: return "端口非法"
        case .missingPrivateKey: return "未选择私钥文件，请在编辑里点击「选择私钥…」"
        case .invalidPrivateKey: return "私钥无法解析（仅支持 ed25519/RSA OpenSSH 私钥）"
        case .agentUnsupported: return "SSH Agent 认证暂未实现"
        }
    }
}

// MARK: - NWConnection ↔ NIO SSH Channel 桥

/// 本地 NWConnection 与 SSH directTCPIP Channel 之间的双向桥。
/// 把 NIO 收到的 ByteBuffer 写到 NWConnection；从 NWConnection 收到的 Data 写到 SSH Channel。
private final class LocalBridge: @unchecked Sendable {
    nonisolated private let inbound: NWConnection
    nonisolated private let onLog: @Sendable (LogLine) -> Void
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var sshChannel: Channel?
    nonisolated(unsafe) private var closed = false

    nonisolated init(inbound: NWConnection, onLog: @escaping @Sendable (LogLine) -> Void) {
        self.inbound = inbound
        self.onLog = onLog
        inbound.start(queue: .global(qos: .userInitiated))
    }

    nonisolated func attach(sshChannel: Channel) {
        lock.withLockSafe { self.sshChannel = sshChannel }
        sshChannel.closeFuture.whenComplete { [weak self] _ in self?.shutdown() }
        pump()
    }

    /// 流水线：receive 不等 SSH writeAndFlush 完成即触发下一次 receive；
    /// SSH channel 内部的 outbound buffer 提供背压。
    nonisolated private func pump() {
        inbound.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.onLog(.init(timestamp: Date(), level: .warn, message: "本地读取失败: \(error)"))
                self.shutdown()
                return
            }
            if let data, !data.isEmpty, let ch = self.lock.withLockSafe({ self.sshChannel }) {
                var buf = ch.allocator.buffer(capacity: data.count)
                buf.writeBytes(data)
                ch.writeAndFlush(buf, promise: nil)
            }
            if isComplete {
                self.shutdown()
            } else {
                self.pump()
            }
        }
    }

    nonisolated func writeOutbound(_ buffer: ByteBuffer) {
        let data = Data(buffer.readableBytesView)
        inbound.send(content: data, completion: .contentProcessed { [weak self] err in
            if let err {
                self?.onLog(.init(timestamp: Date(), level: .warn, message: "本地写入失败: \(err)"))
                self?.shutdown()
            }
        })
    }

    nonisolated func shutdown() {
        let (already, ch): (Bool, Channel?) = lock.withLockSafe {
            let was = closed
            closed = true
            let c = sshChannel
            sshChannel = nil
            return (was, c)
        }
        if already { return }
        inbound.cancel()
        ch?.close(promise: nil)
    }
}

private extension NSLock {
    nonisolated func withLockSafe<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}

/// 把 SSH 通道收到的 ByteBuffer 转发到 NWConnection。
private final class NWBridgeHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    nonisolated let bridge: LocalBridge

    nonisolated init(bridge: LocalBridge) { self.bridge = bridge }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buf = unwrapInboundIn(data)
        bridge.writeOutbound(buf)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        bridge.shutdown()
        context.fireChannelInactive()
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        bridge.shutdown()
        context.fireErrorCaught(error)
    }
}

/// 简易 NIO ↔ NIO 两通道双向桥（供 remote forward 把 SSH 入站接到本地 host:port）。
private final class NIOGlue: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    nonisolated let target: Channel

    nonisolated init(target: Channel) { self.target = target }

    nonisolated func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buf = unwrapInboundIn(data)
        target.writeAndFlush(buf, promise: nil)
    }

    nonisolated func channelInactive(context: ChannelHandlerContext) {
        target.close(promise: nil)
        context.fireChannelInactive()
    }

    nonisolated func errorCaught(context: ChannelHandlerContext, error: Error) {
        target.close(promise: nil)
        context.fireErrorCaught(error)
    }
}

private final class SSHStatusBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var stored: TunnelStatus = .idle

    nonisolated init() {}

    nonisolated var value: TunnelStatus {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

#else  // Citadel 未集成时的占位实现

actor SSHEngine: TunnelEngine {
    nonisolated let tunnelID: UUID
    private let snapshot: TunnelSnapshot
    private let secret: String?
    private let privateKeyMaterial: String?

    nonisolated var status: TunnelStatus { statusBox.value }
    private let statusBox = SSHStatusBox()

    private var onStatus: (@Sendable (TunnelStatus) -> Void)?
    private var onLog: (@Sendable (LogLine) -> Void)?

    init(snapshot: TunnelSnapshot, secret: String?, privateKeyMaterial: String? = nil) {
        self.tunnelID = snapshot.id
        self.snapshot = snapshot
        self.secret = secret
        self.privateKeyMaterial = privateKeyMaterial
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
        transition(.connecting)
        log(.info, "目标 \(snapshot.username)@\(snapshot.host):\(snapshot.port)")
        log(.warn, "未发现 Citadel：在 Xcode → Add Package Dependencies 添加 https://github.com/orlandos-nl/Citadel.git 后重新编译。")
        transition(.failed("SSH backend not configured"))
    }

    func stop() async {
        transition(.stopped)
    }

    private func transition(_ next: TunnelStatus) {
        statusBox.value = next
        onStatus?(next)
    }

    private func log(_ level: LogLine.Level, _ msg: String) {
        onLog?(LogLine(timestamp: Date(), level: level, message: msg))
    }
}

private final class SSHStatusBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var stored: TunnelStatus = .idle

    nonisolated init() {}

    nonisolated var value: TunnelStatus {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

#endif
