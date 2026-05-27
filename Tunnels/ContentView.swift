import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TunnelManager.self) private var manager
    @Query(sort: [SortDescriptor(\Tunnel.name)]) private var tunnels: [Tunnel]
    @State private var selection: Tunnel?
    @State private var editingTunnel: Tunnel?
    @State private var presentNewSheet = false

    var body: some View {
        NavigationSplitView {
            TunnelListView(
                tunnels: tunnels,
                selection: $selection,
                onAdd: addTunnel,
                onDelete: deleteTunnels,
                onEdit: { tunnel in editingTunnel = tunnel }
            )
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
#endif
        } detail: {
            if let tunnel = selection ?? tunnels.first {
                TunnelDetailView(tunnel: tunnel, onEdit: { editingTunnel = tunnel })
                    .id(tunnel.id)
            } else {
                VStack(spacing: 14) {
                    BrandMark(size: 72)
                    Text("未选择隧道")
                        .font(.title3.weight(.medium))
                    Text("从左侧选择一条隧道，或点击左下角 + 新建")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $editingTunnel) { tunnel in
            TunnelEditorView(tunnel: tunnel)
        }
        .onAppear {
            if selection == nil {
                selection = tunnels.first
            }
        }
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .tunnelsRequestNewTunnel)) { _ in
            addTunnel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tunnelsResumeAfterWake)) { notif in
            guard let ids = notif.userInfo?["ids"] as? [UUID] else { return }
            let lookup = Dictionary(uniqueKeysWithValues: tunnels.map { ($0.id, $0) })
            for id in ids {
                if let t = lookup[id] { manager.start(t) }
            }
        }
#endif
    }

    private func addTunnel() {
        let new = Tunnel(name: "新建隧道")
        modelContext.insert(new)
        try? modelContext.save()
        selection = new
        editingTunnel = new
    }

    private func deleteTunnels(_ items: [Tunnel]) {
        for item in items {
            if manager.isRunning(item.id) {
                manager.stop(item)
            }
            if let account = item.keychainAccount {
                Keychain.delete(account: account)
            }
            if let account = item.privateKeyMaterialAccount {
                Keychain.delete(account: account)
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
        if let sel = selection, items.contains(where: { $0.id == sel.id }) {
            selection = nil
        }
    }
}

#Preview {
    ContentView()
        .environment(TunnelManager.shared)
        .modelContainer(for: [Tunnel.self, ForwardRule.self], inMemory: true)
}
