import SwiftUI

struct LogConsoleView: View {
    let tunnelID: UUID
    @Environment(TunnelManager.self) private var manager

    var body: some View {
        let lines = manager.logs(of: tunnelID)
        VStack(alignment: .leading, spacing: 6) {
            if lines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tertiary)
                    Text("暂无日志")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("启动隧道后会显示连接 / 转发 / 错误信息")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(time(line.timestamp))
                                    .foregroundStyle(.secondary)
                                Text(line.level.rawValue.uppercased())
                                    .foregroundStyle(color(for: line.level))
                                    .frame(width: 44, alignment: .leading)
                                Text(line.message)
                                    .foregroundStyle(.primary)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .id(line.id)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
                .onChange(of: manager.logs(of: tunnelID).count) { _, _ in
                    if let last = manager.logs(of: tunnelID).last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func time(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func color(for level: LogLine.Level) -> Color {
        switch level {
        case .info: return .cyan
        case .warn: return .yellow
        case .error: return .red
        case .debug: return .gray
        }
    }
}
