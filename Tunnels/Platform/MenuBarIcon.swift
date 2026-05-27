#if os(macOS)
import AppKit

/// 菜单栏图标：与 App Icon 同款 ⚡ 闪电视觉。
/// 用 SF Symbol，单色模板图（系统自动适配明暗模式 + 自带高 DPI 适配）。
enum TunnelsMenuBarIcon {
    /// idle 状态：描边 bolt
    static var idle: NSImage { symbol("bolt") }

    /// active 状态：实心 bolt（更"亮"，传达"通电"）
    static var active: NSImage { symbol("bolt.fill") }

    private static func symbol(_ name: String) -> NSImage {
        let img = NSImage(
            systemSymbolName: name,
            accessibilityDescription: "Tunnels"
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        img.isTemplate = true
        return img
    }
}
#endif
