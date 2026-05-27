import SwiftUI
import SwiftData

@main
struct TunnelsApp: App {
    @State private var manager = TunnelManager.shared
    @State private var preferences = AppPreferences.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Tunnel.self,
            ForwardRule.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建 ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(manager)
                .environment(preferences)
                .onAppear {
                    preferences.applyActivationPolicy()
#if os(macOS)
                    // 偏好里登录启动开了但系统侧没注册（用户手动取消过）→ 同步一次
                    if preferences.launchAtLogin && !preferences.launchAtLoginIsRegistered {
                        preferences.applyLaunchAtLogin()
                    }
#endif
                }
#if os(macOS)
                .frame(minWidth: 760, minHeight: 520)
#endif
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
#endif

#if os(macOS)
        Settings {
            PreferencesView()
                .environment(preferences)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(manager)
                .environment(preferences)
                .modelContainer(sharedModelContainer)
        } label: {
            Image(nsImage: manager.activeIDs.isEmpty
                  ? TunnelsMenuBarIcon.idle
                  : TunnelsMenuBarIcon.active)
        }
        .menuBarExtraStyle(.menu)
#endif
    }
}
