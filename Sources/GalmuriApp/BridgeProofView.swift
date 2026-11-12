import SwiftUI
import GalmuriCore

struct BridgeProofView: View {
    let directory: URL
    @Environment(\.dismiss) private var dismiss
    @State private var requests: [BridgeProof] = []
    @State private var approved = Set<UUID>()
    @State private var busy = false
    @State private var error: String?
    @State private var apiShowing = false

    init(directory: URL, requests: [BridgeProof] = []) {
        self.directory = directory
        _requests = State(initialValue: requests)
    }

    private var store: BridgeProofStore {
        BridgeProofStore(workspace: directory, variant: Bundle.main.object(forInfoDictionaryKey: "GalmuriBuildConfiguration") as? String ?? "debug")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("bridge.title").font(.headline)
                Spacer()
                Button("common.close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("bridge.detail").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("bridge.refresh") {
                busy = true; error = nil
                let source = store
                Task {
                    do {
                        requests = try await Task.detached { try source.requests() }.value
                        approved.formIntersection(Set(requests.map(\.id)))
                    } catch { self.error = L("bridge.failure") }
                    busy = false
                }
            }.disabled(busy)
            Button("api.title") { apiShowing = true }
            if let error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if requests.isEmpty { Text("bridge.empty").foregroundStyle(.secondary) }
                    ForEach(requests) { request in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(request.name).font(.headline).textSelection(.enabled)
                            Text(request.code).font(.title2.monospacedDigit()).textSelection(.enabled)
                                .accessibilityLabel(String(format: L("bridge.code"), request.code))
                            Text(request.installationID.uuidString.lowercased()).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if approved.contains(request.id) {
                                Label("bridge.approved", systemImage: "checkmark.circle")
                            } else {
                                Button("bridge.approve") {
                                    busy = true; error = nil
                                    let source = store
                                    Task {
                                        do {
                                            try await Task.detached { try source.approve(request) }.value
                                            approved.insert(request.id)
                                        } catch { self.error = L("bridge.failure") }
                                        busy = false
                                    }
                                }.disabled(busy)
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("bridge.limit").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).sheet(isPresented: $apiShowing) { APIWorkspaceView(directory: directory) }
    }
}
