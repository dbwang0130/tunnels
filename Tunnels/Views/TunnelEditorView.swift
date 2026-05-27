import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct TunnelEditorView: View {
    @Bindable var tunnel: Tunnel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var passwordLoaded: Bool = false
    @State private var keyImportError: String?
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("名称", text: $tunnel.name)
                    TextField("备注", text: $tunnel.note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    Picker("后端", selection: bindingFor(\.backend)) {
                        ForEach(TunnelBackend.allCases) { backend in
                            VStack(alignment: .leading) {
                                Text(backend.displayName)
                                Text(backend.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(backend)
                        }
                    }
                    TextField("主机", text: $tunnel.host)
                        .textContentType(.URL)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
#endif
                    portStepper
                    TextField("用户名", text: $tunnel.username)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                } header: {
                    Text("服务器")
                } footer: {
                    Text("主机可以是域名或 IP；SSH 默认端口 22；用户名是登录服务器使用的账号。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if tunnel.backend == .ssh {
                    Section {
                        Picker("方式", selection: bindingFor(\.authMethod)) {
                            ForEach(AuthMethod.allCases) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        switch tunnel.authMethod {
                        case .password:
                            SecureField("密码", text: $password)
                                .onAppear(perform: loadPassword)
                            Text("密码会以加密方式保存在 Keychain 中。")
                                .font(.caption).foregroundStyle(.secondary)
                        case .privateKey:
                            privateKeyPickerRow
                            SecureField("私钥口令（可选）", text: $password)
                                .onAppear(perform: loadPassword)
                            if let err = keyImportError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        case .agent:
                            Text("将使用系统 SSH Agent 提供的身份（暂未实现，将报错回退）。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("身份验证")
                    } footer: {
                        Text("沙盒应用无法直接读 ~/.ssh，必须使用「选择私钥…」按钮选取，文件内容会保存到 macOS Keychain。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("应用启动时自动连接", isOn: $tunnel.autoStart)
                    Toggle("断线后自动重连", isOn: $tunnel.autoReconnect)
                    Toggle("启用压缩", isOn: $tunnel.compression)
                    Stepper(
                        "保活间隔: \(tunnel.keepAliveInterval) 秒",
                        value: $tunnel.keepAliveInterval,
                        in: 0...600,
                        step: 5
                    )
                } header: {
                    Text("行为")
                } footer: {
                    Text("保活：定期向服务器发心跳防止 NAT/防火墙断开（0 表示禁用）。压缩对慢网络有帮助，但会消耗 CPU。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑隧道")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(tunnel.host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }

    private var portStepper: some View {
        HStack {
            Text("端口")
            Spacer()
            TextField("22", value: $tunnel.port, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
            Stepper("", value: $tunnel.port, in: 1...65535)
                .labelsHidden()
        }
    }

    private func bindingFor<T>(_ keyPath: ReferenceWritableKeyPath<Tunnel, T>) -> Binding<T> {
        Binding(get: { tunnel[keyPath: keyPath] }, set: { tunnel[keyPath: keyPath] = $0 })
    }

    private var privateKeyPickerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(privateKeyDisplayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if tunnel.privateKeyMaterialAccount != nil {
                    Text("已存入 Keychain").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("尚未选择文件").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("选择私钥…") { presentKeyPicker() }
            if tunnel.privateKeyMaterialAccount != nil {
                Button(role: .destructive) { clearPrivateKey() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
#if os(iOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .text, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importPrivateKey(from: url, accessSecurityScope: true)
            case .failure(let error):
                keyImportError = error.localizedDescription
            }
        }
#endif
    }

    private var privateKeyDisplayName: String {
        if let path = tunnel.privateKeyPath, !path.isEmpty {
            return (path as NSString).lastPathComponent
        }
        return "未选择私钥"
    }

    private func presentKeyPicker() {
        keyImportError = nil
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 OpenSSH 私钥（id_ed25519、id_rsa 等）"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            importPrivateKey(from: url, accessSecurityScope: false)
        }
#else
        showFileImporter = true
#endif
    }

    private func importPrivateKey(from url: URL, accessSecurityScope: Bool) {
        let scoped = accessSecurityScope && url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            keyImportError = "读取文件失败: \(error.localizedDescription)"
            return
        }
        guard let pem = String(data: data, encoding: .utf8) else {
            keyImportError = "私钥不是 UTF-8 文本"
            return
        }
        guard pem.contains("PRIVATE KEY") else {
            keyImportError = "文件看起来不是 OpenSSH 私钥"
            return
        }
        let account = tunnel.privateKeyMaterialAccount ?? Keychain.newAccountIdentifier()
        do {
            try Keychain.save(pem, account: account)
        } catch {
            keyImportError = "保存到安全存储失败: \(error.localizedDescription)"
            return
        }
        // 验证：写入后立刻 load 回来确认
        guard (try? Keychain.load(account: account)) ?? nil != nil else {
            keyImportError = "保存后回读失败，可能是存储权限受限"
            return
        }
        tunnel.privateKeyMaterialAccount = account
        tunnel.privateKeyPath = url.path
        keyImportError = nil
    }

    private func clearPrivateKey() {
        if let acc = tunnel.privateKeyMaterialAccount {
            Keychain.delete(account: acc)
        }
        tunnel.privateKeyMaterialAccount = nil
        tunnel.privateKeyPath = nil
    }

    private func loadPassword() {
        guard !passwordLoaded else { return }
        passwordLoaded = true
        if let account = tunnel.keychainAccount,
           let stored = (try? Keychain.load(account: account)).flatMap({ $0 }) {
            password = stored
        }
    }

    private func save() {
        if tunnel.backend == .ssh && (tunnel.authMethod == .password || tunnel.authMethod == .privateKey) {
            if !password.isEmpty {
                let account = tunnel.keychainAccount ?? Keychain.newAccountIdentifier()
                try? Keychain.save(password, account: account)
                tunnel.keychainAccount = account
            } else if let account = tunnel.keychainAccount {
                Keychain.delete(account: account)
                tunnel.keychainAccount = nil
            }
        } else if let account = tunnel.keychainAccount {
            Keychain.delete(account: account)
            tunnel.keychainAccount = nil
        }
        tunnel.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}
