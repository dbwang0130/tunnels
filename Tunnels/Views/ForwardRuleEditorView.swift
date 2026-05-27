import SwiftUI

struct ForwardRuleEditorView: View {
    let existing: ForwardRule?
    let onSave: (ForwardRule) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: ForwardKind
    @State private var bindAddress: String
    @State private var bindPort: Int
    @State private var targetHost: String
    @State private var targetPort: Int
    @State private var enabled: Bool
    @State private var note: String

    init(rule: ForwardRule?, onSave: @escaping (ForwardRule) -> Void) {
        self.existing = rule
        self.onSave = onSave
        _kind = State(initialValue: rule?.kind ?? .local)
        _bindAddress = State(initialValue: rule?.bindAddress ?? "127.0.0.1")
        _bindPort = State(initialValue: rule?.bindPort ?? 8080)
        _targetHost = State(initialValue: rule?.targetHost ?? "")
        _targetPort = State(initialValue: rule?.targetPort ?? 80)
        _enabled = State(initialValue: rule?.enabled ?? true)
        _note = State(initialValue: rule?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("方向", selection: $kind) {
                        ForEach(ForwardKind.allCases) { k in
                            Label(k.displayName, systemImage: k.symbolName).tag(k)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(kind == .dynamic ? "本地 SOCKS 监听" : "本地监听") {
                    TextField("绑定地址", text: $bindAddress)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                    portField(label: "本地端口", value: $bindPort)
                }

                if kind != .dynamic {
                    Section(kind == .local ? "通过隧道访问的目标" : "本地可达的目标") {
                        TextField("目标主机", text: $targetHost)
#if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
#endif
                        portField(label: "目标端口", value: $targetPort)
                    }
                }

                Section {
                    Toggle("启用", isOn: $enabled)
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "新建规则" : "编辑规则")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { commit() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 460)
    }

    private var isValid: Bool {
        guard bindPort > 0 && bindPort <= 65535 else { return false }
        if kind == .dynamic { return true }
        return !targetHost.trimmingCharacters(in: .whitespaces).isEmpty
            && targetPort > 0 && targetPort <= 65535
    }

    private func portField(label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
            Stepper("", value: value, in: 1...65535)
                .labelsHidden()
        }
    }

    private func commit() {
        if let existing {
            existing.kind = kind
            existing.bindAddress = bindAddress
            existing.bindPort = bindPort
            existing.targetHost = targetHost
            existing.targetPort = targetPort
            existing.enabled = enabled
            existing.note = note
            onSave(existing)
        } else {
            let new = ForwardRule(
                kind: kind,
                bindAddress: bindAddress,
                bindPort: bindPort,
                targetHost: targetHost,
                targetPort: targetPort,
                enabled: enabled,
                note: note
            )
            onSave(new)
        }
        dismiss()
    }
}
