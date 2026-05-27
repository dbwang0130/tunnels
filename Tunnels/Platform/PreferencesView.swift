#if os(macOS)
import SwiftUI

struct PreferencesView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            TunnelDefaultsTab()
                .tabItem { Label("隧道", systemImage: "point.3.connected.trianglepath.dotted") }
            SecurityTab()
                .tabItem { Label("安全", systemImage: "lock.shield") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .scenePadding()
        .frame(width: 520, height: 380)
    }
}

// MARK: - 通用

private struct GeneralTab: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section {
                Toggle("登录时自动启动 Tunnels", isOn: $prefs.launchAtLogin)
                    .disabled(!preferences.launchAtLoginAvailable)
                Toggle("启动时打开主窗口", isOn: $prefs.openMainWindowAtLaunch)
            } header: {
                Text("启动")
            } footer: {
                Text("登录启动需要 macOS 13 及以上。第一次开启时系统可能要求确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("仅显示菜单栏图标（隐藏 Dock）", isOn: $prefs.menuBarOnly)
            } header: {
                Text("外观")
            } footer: {
                Text("打开后，Tunnels 不会出现在 Dock；仍可通过菜单栏图标打开主窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 隧道默认

private struct TunnelDefaultsTab: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section {
                Stepper(
                    "保活间隔：\(prefs.defaultKeepAlive) 秒",
                    value: $prefs.defaultKeepAlive,
                    in: 0...600,
                    step: 5
                )
                Toggle("启用压缩", isOn: $prefs.defaultCompression)
            } header: {
                Text("连接默认值")
            } footer: {
                Text("这些值会作为新建隧道的默认值；已有隧道不会被自动改写。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("断线后自动重连", isOn: $prefs.defaultAutoReconnect)
                Stepper(
                    "首次重连退避：\(prefs.reconnectBackoff) 秒",
                    value: $prefs.reconnectBackoff,
                    in: 1...60,
                    step: 1
                )
            } header: {
                Text("重连策略")
            } footer: {
                Text("断线后将以指数退避（首次 N 秒、之后逐次翻倍至 60 秒上限）尝试重连。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 安全

private struct SecurityTab: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section {
                Picker("Host key 策略", selection: $prefs.hostKeyPolicy) {
                    ForEach(HostKeyPolicy.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
            } header: {
                Text("服务器验证")
            } footer: {
                Text("严格 / 首次询问 模式目前会回退到「接受任意」直到 known_hosts 功能完成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(
                    "保留最近：\(prefs.logRetention) 行",
                    value: $prefs.logRetention,
                    in: 100...5000,
                    step: 100
                )
            } header: {
                Text("日志")
            } footer: {
                Text("日志仅保留在内存中，应用退出后清空。不会上传到任何地方。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 关于

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
            Text("Tunnels")
                .font(.title2.weight(.semibold))
            Text(versionString)
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 6) {
                Label("SSH 后端基于 [Citadel](https://github.com/orlandos-nl/Citadel) 0.12.1", systemImage: "shippingbox")
                Label("网络抽象基于 [SwiftNIO](https://github.com/apple/swift-nio)", systemImage: "network")
                Label("UI 基于 SwiftUI + SwiftData", systemImage: "paintbrush")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .padding()
    }

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "版本 \(v) (\(b))"
    }
}
#endif
