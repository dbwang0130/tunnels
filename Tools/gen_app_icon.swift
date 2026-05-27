#!/usr/bin/env swift
// 用 BrandMark 风格批量生成 macOS / iOS AppIcon PNG。
// 用法：cd /Users/dbw/Projects/Tunnels && swift Tools/gen_app_icon.swift

import AppKit
import CoreGraphics

let outDir = URL(fileURLWithPath: "Tunnels/Assets.xcassets/AppIcon.appiconset")

// 颜色主题
struct Theme {
    let bgTop: NSColor
    let bgBottom: NSColor
    let mark: NSColor
    let markGradientEnd: NSColor
}

// VS Code 风底色：白色 squircle 背景，主色蓝
let light = Theme(
    bgTop: NSColor(calibratedWhite: 0.99, alpha: 1),
    bgBottom: NSColor(calibratedWhite: 0.93, alpha: 1),
    mark: NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.80, alpha: 1),
    markGradientEnd: NSColor(calibratedRed: 0.20, green: 0.62, blue: 0.98, alpha: 1)
)

let dark = Theme(
    bgTop: NSColor(calibratedWhite: 0.99, alpha: 1),
    bgBottom: NSColor(calibratedWhite: 0.93, alpha: 1),
    mark: NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.80, alpha: 1),
    markGradientEnd: NSColor(calibratedRed: 0.20, green: 0.62, blue: 0.98, alpha: 1)
)

let tinted = Theme(
    bgTop: .black,
    bgBottom: .black,
    mark: .white,
    markGradientEnd: NSColor(calibratedWhite: 0.7, alpha: 1)
)

func render(size: CGFloat, theme: Theme, macSquircle: Bool, fileURL: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    let ctx = g.cgContext

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.clear(canvas)

    // macOS 26 Liquid Glass / iOS：系统会强制套一层 squircle 容器并自行 mask 圆角。
    // 只画纯矩形铺满整个 1024×1024，圆角完全交给系统。
    let body = canvas
    ctx.saveGState()

    let cs = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [theme.bgTop.cgColor, theme.bgBottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )

    // === ⚡️ Apple Color Emoji 渲染到画布中央 ===
    // 直接用系统 Apple Color Emoji 字体——苹果自家设计的字形带渐变/高光/阴影
    let s = body.width
    let emoji = "⚡️"
    let fontSize = s * 0.78
    let font = NSFont(name: "Apple Color Emoji", size: fontSize)
        ?? NSFont.systemFont(ofSize: fontSize)

    // 给 emoji 加一点 drop shadow，增加"浮起来"立体感
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.010)
    shadow.shadowBlurRadius = s * 0.025

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .shadow: shadow
    ]
    let str = NSAttributedString(string: emoji, attributes: attrs)
    let textSize = str.size()
    let drawPoint = CGPoint(
        x: (s - textSize.width) * 0.5,
        y: (s - textSize.height) * 0.5
    )
    str.draw(at: drawPoint)

    ctx.restoreGState()  // pop bg
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("PNG encode failed for \(fileURL.lastPathComponent)\n".data(using: .utf8)!)
        exit(1)
    }
    try! data.write(to: fileURL)
    print("✓ \(fileURL.lastPathComponent) (\(Int(size))×\(Int(size)))")
}

// macOS 各尺寸
struct MacEntry { let name: String; let size: CGFloat }
let macEntries: [MacEntry] = [
    .init(name: "mac_16.png",   size: 16),
    .init(name: "mac_32b.png",  size: 32),
    .init(name: "mac_32.png",   size: 32),
    .init(name: "mac_64.png",   size: 64),
    .init(name: "mac_128.png",  size: 128),
    .init(name: "mac_256b.png", size: 256),
    .init(name: "mac_256.png",  size: 256),
    .init(name: "mac_512b.png", size: 512),
    .init(name: "mac_512.png",  size: 512),
    .init(name: "mac_1024.png", size: 1024),
]

for e in macEntries {
    render(size: e.size, theme: light, macSquircle: true, fileURL: outDir.appendingPathComponent(e.name))
}

render(size: 1024, theme: light,  macSquircle: false, fileURL: outDir.appendingPathComponent("ios_light.png"))
render(size: 1024, theme: dark,   macSquircle: false, fileURL: outDir.appendingPathComponent("ios_dark.png"))
render(size: 1024, theme: tinted, macSquircle: false, fileURL: outDir.appendingPathComponent("ios_tinted.png"))

print("\n全部生成完毕：\(outDir.path)")
