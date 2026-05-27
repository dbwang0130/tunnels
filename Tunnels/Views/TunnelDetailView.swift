import SwiftUI
import SwiftData

struct TunnelDetailView: View {
    @Bindable var tunnel: Tunnel
    let onEdit: () -> Void

    @Environment(TunnelManager.self) private var manager
    @Environment(\.modelContext) private var modelContext
    @State private var addingRule = false
    @State private var editingRule: ForwardRule?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                statusSection
                rulesSection
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            logPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(tunnel.name)
#if os(macOS)
        .navigationSubtitle(tunnel.displayDestination)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let running = manager.isRunning(tunnel.id)
                Button {
                    manager.toggle(tunnel)
                } label: {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .foregroundStyle(running ? Color.red : Color.green)
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(running ? "停止隧道（⌘R）" : "启动隧道（⌘R）")
                .keyboardShortcut("r", modifiers: .command)
            }
            ToolbarItem {
                Button(action: onEdit) {
                    Label("编辑", systemImage: "slider.horizontal.3")
                }
                .help("编辑隧道（⌘E）")
                .keyboardShortcut("e", modifiers: .command)
            }
        }
        .sheet(isPresented: $addingRule) {
            ForwardRuleEditorView(rule: nil) { newRule in
                tunnel.rules.append(newRule)
                tunnel.updatedAt = Date()
                try? modelContext.save()
                manager.reapplyRules(of: tunnel)
            }
        }
        .sheet(item: $editingRule) { rule in
            ForwardRuleEditorView(rule: rule) { _ in
                tunnel.updatedAt = Date()
                try? modelContext.save()
                manager.reapplyRules(of: tunnel)
            }
        }
    }

    // MARK: 状态（合并为一行）

    private var statusSection: some View {
        Section {
            HStack(spacing: 10) {
                StatusDot(status: manager.status(of: tunnel.id))
                Text(manager.status(of: tunnel.id).displayText)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(backendBadge)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.5)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            if !tunnel.note.isEmpty {
                LabeledContent("备注") {
                    Text(tunnel.note)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var backendBadge: String {
        tunnel.backend == .ssh ? "SSH" : "TCP"
    }

    // MARK: 转发规则（紧凑行）

    private var rulesSection: some View {
        Section {
            if tunnel.rules.isEmpty {
                Text("暂无转发规则，点击右上角 + 添加一条。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tunnel.rules) { rule in
                    ruleRow(rule)
                }
            }
        } header: {
            HStack {
                Text("转发规则")
                HelpPopover {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("**本地 (-L)**：把本地端口映射到通过隧道访问的远程目标。常用于「在本机访问远端内网数据库/Web」。")
                        Text("**远程 (-R)**：把远程服务器上的端口映射到本机或本机可达的服务。常用于「把本地服务暴露到远端」。")
                        Text("**动态 (-D)**：在本机起 SOCKS5 代理，所有走该代理的流量经隧道转发（暂未实现）。")
                    }
                    .font(.callout)
                    .frame(maxWidth: 360, alignment: .leading)
                    .padding(14)
                }
                Spacer()
                Button {
                    addingRule = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加转发规则")
            }
        }
    }

    private func ruleRow(_ rule: ForwardRule) -> some View {
        let mono = Font.system(.callout, design: .monospaced).monospacedDigit()
        return HStack(spacing: 12) {
            kindBadge(rule.kind)
            Text("\(rule.bindAddress):\(rule.bindPort)")
                .font(mono)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(rule.kind == .dynamic ? "SOCKS5" : "\(rule.targetHost):\(rule.targetPort)")
                .font(mono)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            if !rule.note.isEmpty {
                Text(rule.note)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { newValue in
                    rule.enabled = newValue
                    tunnel.updatedAt = Date()
                    try? modelContext.save()
                    manager.reapplyRules(of: tunnel)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .opacity(rule.enabled ? 1.0 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: rule.enabled)
        .padding(.vertical, 2)
        .contextMenu {
            Button("编辑…") { editingRule = rule }
            Divider()
            Button("删除", role: .destructive) {
                tunnel.rules.removeAll { $0.id == rule.id }
                modelContext.delete(rule)
                try? modelContext.save()
                manager.reapplyRules(of: tunnel)
            }
        }
        .onTapGesture(count: 2) { editingRule = rule }
        .help("双击编辑")
    }

    @ViewBuilder
    private func kindBadge(_ kind: ForwardKind) -> some View {
        let (letter, tint): (String, Color) = {
            switch kind {
            case .local:   return ("L", .blue)
            case .remote:  return ("R", .orange)
            case .dynamic: return ("D", .purple)
            }
        }()
        Text(letter)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 20, height: 20)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .help(kind.displayName)
    }

    // MARK: 日志

    private var hasLogs: Bool {
        !manager.logs(of: tunnel.id).isEmpty
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("日志")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HelpPopover {
                    Text("仅保留最近 500 行；关闭隧道不会清空日志，重新启动时也不会保留到下次。")
                        .font(.callout)
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(14)
                }
                Spacer()
                Text("\(manager.logs(of: tunnel.id).count) 行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    manager.clearLogs(of: tunnel.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!hasLogs)
                .help("清空日志")
            }
            LogConsoleView(tunnelID: tunnel.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

private struct HelpPopover<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            content()
        }
        .help("查看说明")
    }
}
