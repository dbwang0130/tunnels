import Foundation
import SwiftUI

#if os(macOS)
import AppKit
import ServiceManagement
#endif

enum HostKeyPolicy: String, Codable, CaseIterable, Identifiable {
    case acceptAny      // 接受任何 host key
    case strict         // 严格：必须匹配已记录指纹（未实现时回退到 acceptAny）
    case ask            // 首次连接询问（未实现时回退到 acceptAny）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .acceptAny: return "接受任意（不验证）"
        case .strict:    return "严格（必须已信任的指纹）"
        case .ask:       return "首次连接询问"
        }
    }
}

@Observable
@MainActor
final class AppPreferences {
    static let shared = AppPreferences()

    private let ud = UserDefaults.standard

    // MARK: 通用
    var menuBarOnly: Bool {
        didSet {
            ud.set(menuBarOnly, forKey: "pref.menuBarOnly")
            applyActivationPolicy()
        }
    }

    var launchAtLogin: Bool {
        didSet {
            ud.set(launchAtLogin, forKey: "pref.launchAtLogin")
            applyLaunchAtLogin()
        }
    }

    var openMainWindowAtLaunch: Bool {
        didSet { ud.set(openMainWindowAtLaunch, forKey: "pref.openMainAtLaunch") }
    }

    // MARK: 隧道默认
    var defaultKeepAlive: Int {
        didSet { ud.set(defaultKeepAlive, forKey: "pref.defaultKeepAlive") }
    }

    var defaultCompression: Bool {
        didSet { ud.set(defaultCompression, forKey: "pref.defaultCompression") }
    }

    var defaultAutoReconnect: Bool {
        didSet { ud.set(defaultAutoReconnect, forKey: "pref.defaultAutoReconnect") }
    }

    var reconnectBackoff: Int {
        didSet { ud.set(reconnectBackoff, forKey: "pref.reconnectBackoff") }
    }

    // MARK: 安全
    var hostKeyPolicy: HostKeyPolicy {
        didSet { ud.set(hostKeyPolicy.rawValue, forKey: "pref.hostKeyPolicy") }
    }

    var logRetention: Int {
        didSet { ud.set(logRetention, forKey: "pref.logRetention") }
    }

    private init() {
        self.menuBarOnly = ud.bool(forKey: "pref.menuBarOnly")
        self.launchAtLogin = ud.bool(forKey: "pref.launchAtLogin")
        self.openMainWindowAtLaunch = ud.object(forKey: "pref.openMainAtLaunch") as? Bool ?? true
        self.defaultKeepAlive = (ud.object(forKey: "pref.defaultKeepAlive") as? Int) ?? 30
        self.defaultCompression = ud.bool(forKey: "pref.defaultCompression")
        self.defaultAutoReconnect = (ud.object(forKey: "pref.defaultAutoReconnect") as? Bool) ?? true
        self.reconnectBackoff = (ud.object(forKey: "pref.reconnectBackoff") as? Int) ?? 5
        let raw = ud.string(forKey: "pref.hostKeyPolicy") ?? HostKeyPolicy.acceptAny.rawValue
        self.hostKeyPolicy = HostKeyPolicy(rawValue: raw) ?? .acceptAny
        self.logRetention = (ud.object(forKey: "pref.logRetention") as? Int) ?? 500
    }

    func applyActivationPolicy() {
#if os(macOS)
        let policy: NSApplication.ActivationPolicy = menuBarOnly ? .accessory : .regular
        NSApp.setActivationPolicy(policy)
        if !menuBarOnly {
            NSApp.activate(ignoringOtherApps: true)
        }
#endif
    }

    func applyLaunchAtLogin() {
#if os(macOS)
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 静默失败：UserDefaults 仍然记录用户偏好；下一次启动时再次尝试同步
            NSLog("LaunchAtLogin sync failed: \(error)")
        }
#endif
    }

    var launchAtLoginAvailable: Bool {
#if os(macOS)
        return true
#else
        return false
#endif
    }

    /// 当前真实的注册状态（可能与 UserDefaults 偏好不一致，例如用户在系统设置里手动取消）
    var launchAtLoginIsRegistered: Bool {
#if os(macOS)
        return SMAppService.mainApp.status == .enabled
#else
        return false
#endif
    }
}
