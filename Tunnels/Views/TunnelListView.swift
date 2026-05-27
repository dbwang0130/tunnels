import SwiftUI

struct TunnelListView: View {
    let tunnels: [Tunnel]
    @Binding var selection: Tunnel?
    let onAdd: () -> Void
    let onDelete: ([Tunnel]) -> Void
    let onEdit: (Tunnel) -> Void

    @Environment(TunnelManager.self) private var manager

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            bottomBar
        }
        .navigationTitle("Tunnels")
    }

    @ViewBuilder
    private var list: some View {
        if tunnels.isEmpty {
            emptyState
        } else {
            List(selection: $selection) {
                Section("隧道") {
                    ForEach(tunnels) { tunnel in
                        TunnelRow(
                            tunnel: tunnel,
                            isSelected: selection == tunnel,
                            onEdit: { onEdit(tunnel) }
                        )
                            .tag(tunnel)
                            .contextMenu {
                                Button(manager.isRunning(tunnel.id) ? "停止" : "启动") {
                                    manager.toggle(tunnel)
                                }
                                Button("编辑…") { onEdit(tunnel) }
                                Divider()
                                Button("删除", role: .destructive) { onDelete([tunnel]) }
                            }
                    }
                    .onDelete { indexSet in
                        onDelete(indexSet.map { tunnels[$0] })
                    }
                }
            }
#if os(macOS)
            .listStyle(.sidebar)
#endif
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.borderless)
            .help("新建隧道")

            Divider().frame(height: 12)

            Button {
                if let s = selection { onDelete([s]) }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .help("删除选中的隧道")

            Spacer()

            if !tunnels.isEmpty {
                Text(activeSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 10)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: manager.activeIDs.count)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
#if os(macOS)
        .background(.bar)
#endif
    }

    private var activeSummary: String {
        let n = manager.activeIDs.count
        return n == 0 ? "全部停止" : "运行中 \(n) / \(tunnels.count)"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            BrandMark(size: 44)
            Text("尚无隧道")
                .font(.subheadline.weight(.medium))
            Text("点击下方 + 创建")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TunnelRow: View {
    let tunnel: Tunnel
    let isSelected: Bool
    let onEdit: () -> Void
    @Environment(TunnelManager.self) private var manager
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: manager.status(of: tunnel.id), onAccent: isSelected)
            VStack(alignment: .leading, spacing: 1) {
                Text(tunnel.name)
                    .lineLimit(1)
                Text(tunnel.displayDestination)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            // 选中态：不显示行内启停按钮（detail 工具栏有更大的）
            // 非选中态：hover 时显示；运行中也常驻显示
            if !isSelected && (hovering || manager.isRunning(tunnel.id)) {
                actionButton
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.2, bounce: 0.2), value: hovering)
    }

    @ViewBuilder
    private var actionButton: some View {
        let running = manager.isRunning(tunnel.id)
        Button {
            manager.toggle(tunnel)
        } label: {
            Image(systemName: running ? "stop.fill" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 18, height: 18)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(running ? Color.red : Color.accentColor)
        .help(running ? "停止" : "启动")
    }
}

/// Tunnels 品牌符号：左右两个端点 + 中间 S 形管道。
/// 隐喻 SSH 隧道：本机端口 → 加密通道 → 远端服务。
struct BrandMark: View {
    var size: CGFloat = 56
    var tint: Color = .accentColor

    var body: some View {
        let dot = size * 0.18
        let stroke = size * 0.075
        ZStack {
            PipePath()
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0.45), tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .padding(.horizontal, size * 0.18)
            Circle()
                .fill(tint)
                .frame(width: dot, height: dot)
                .position(x: size * 0.18, y: size * 0.5)
            Circle()
                .fill(tint)
                .frame(width: dot, height: dot)
                .position(x: size * 0.82, y: size * 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Tunnels")
    }
}

private struct PipePath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY
        let liftA = rect.height * 0.28
        let liftB = rect.height * 0.28
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: y),
            control1: CGPoint(x: rect.minX + rect.width * 0.35, y: y - liftA),
            control2: CGPoint(x: rect.maxX - rect.width * 0.35, y: y + liftB)
        )
        return p
    }
}

struct StatusDot: View {
    let status: TunnelStatus
    var onAccent: Bool = false
    @State private var pulse = false

    private var isPulsing: Bool {
        status == .connecting || status == .reconnecting
    }

    private var dotColor: Color {
        onAccent ? .white : status.color
    }

    private var haloOpacity: Double {
        onAccent ? 0.55 : 0.22
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(dotColor.opacity(haloOpacity))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse && isPulsing ? 1.35 : 1.0)
                .opacity(pulse && isPulsing ? 0.0 : 1.0)
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: (!onAccent && status == .connected) ? status.color.opacity(0.55) : .clear, radius: 3)
            if case .failed = status {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(onAccent ? Color.red : .white)
            }
        }
        .frame(width: 14, height: 14)
        .animation(isPulsing ? .easeOut(duration: 1.1).repeatForever(autoreverses: false) : .default, value: pulse)
        .onAppear { pulse = true }
        .onChange(of: isPulsing) { _, newValue in
            pulse = false
            if newValue { DispatchQueue.main.async { pulse = true } }
        }
    }
}
