#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct MenuBarContent: View {
    @Environment(TunnelManager.self) private var manager
    @Environment(AppPreferences.self) private var preferences
    @Query(sort: [SortDescriptor(\Tunnel.name)]) private var tunnels: [Tunnel]

    var body: some View {
        // 顶部 section 标题（运行计数）
        let active = manager.activeIDs.count
        Section(active == 0 ? "Tunnels — 全部停止" : "Tunnels — 运行中 \(active)/\(tunnels.count)") {
            if tunnels.isEmpty {
                Text("尚未创建隧道").disabled(true)
            } else {
                ForEach(tunnels) { tunnel in
                    Button {
                        manager.toggle(tunnel)
                    } label: {
                        Label {
                            Text(menuTitle(for: tunnel))
                        } icon: {
                            Image(systemName: iconName(for: tunnel))
                        }
                    }
                }
            }
        }

        Divider()

        if !tunnels.isEmpty {
            Button("全部启动") { startAll() }
                .disabled(manager.activeIDs.count == tunnels.count)
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("全部停止") { stopAll() }
                .disabled(manager.activeIDs.isEmpty)
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Divider()
        }

        Button("新建隧道…") { newTunnel() }
            .keyboardShortcut("n", modifiers: .command)
        Button("打开主窗口") { openMainWindow() }
            .keyboardShortcut("0", modifiers: .command)
        SettingsLink { Text("偏好…") }
            .keyboardShortcut(",", modifiers: .command)

        Divider()
        Button("退出 Tunnels") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func menuTitle(for tunnel: Tunnel) -> String {
        let host = tunnel.host.isEmpty ? "未配置" : "\(tunnel.host):\(tunnel.port)"
        return "\(tunnel.name)  ·  \(host)"
    }

    private func iconName(for tunnel: Tunnel) -> String {
        let status = manager.status(of: tunnel.id)
        switch status {
        case .connected:    return "circle.fill"
        case .connecting, .reconnecting, .stopping: return "circle.dotted"
        case .failed:       return "exclamationmark.triangle.fill"
        default:            return "circle"
        }
    }

    private func startAll() {
        for t in tunnels where !manager.isRunning(t.id) {
            manager.start(t)
        }
    }

    private func stopAll() {
        for t in tunnels where manager.isRunning(t.id) {
            manager.stop(t)
        }
    }

    private func newTunnel() {
        openMainWindow()
        NotificationCenter.default.post(name: .tunnelsRequestNewTunnel, object: nil)
    }

    private func openMainWindow() {
        if preferences.menuBarOnly {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

extension Notification.Name {
    static let tunnelsRequestNewTunnel = Notification.Name("tunnelsRequestNewTunnel")
}
#endif
