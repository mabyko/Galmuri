import SwiftUI
import GalmuriCore

func localizedCount(_ key: String, _ count: Int) -> String {
    // Plural rules follow the app language, which can differ from the system region.
    String(format: L(key), locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"), count)
}

// Core errors remain independent of the app bundle; translate their copy at the UI boundary.
func localizedAppMessage(_ message: String) -> String {
    if message.contains("\n") {
        return message.components(separatedBy: "\n").map(localizedAppMessage).joined(separator: "\n")
    }
    for (prefix, key) in [("Invalid bookmark data: ", "error.invalid"), ("Read-only format: ", "error.unsupported")] {
        if message.hasPrefix(prefix) {
            return String(format: L(key), locale: Locale.current, L(String(message.dropFirst(prefix.count))))
        }
    }
    return L(message)
}

func localizedMovePaths(_ paths: String, existingPaths: Set<String>) -> String {
    paths.components(separatedBy: "\n").map { line in
        let prefix = "Removed: "
        let id = String(line.dropFirst(prefix.count))
        if !existingPaths.contains(line), line.hasPrefix(prefix), UUID(uuidString: id) != nil {
            return String(format: L("review.removedIdentity"), locale: Locale.current, id)
        }
        return line
    }.joined(separator: "\n")
}

struct AppErrorNotice: View {
    @Bindable var store: AppStore

    var body: some View {
        if let error = store.error {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
                Text(localizedAppMessage(error)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if store.needsReconnect { Button("profile.reconnect") { store.reconnect() }.disabled(store.busy) }
                Button("common.dismissError") { store.error = nil }.buttonStyle(.borderless)
            }
            .font(.callout).foregroundStyle(.orange).padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityElement(children: .contain)
        }
    }
}

struct BookmarkSnapshot: View {
    let tree: BookmarkTree
    let id: String
    var includesDescendants = false

    private var nodes: [Bookmark] {
        (includesDescendants ? tree.descendants(of: id).sorted() : [id]).compactMap { tree.nodes[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(nodes) { node in
                VStack(alignment: .leading, spacing: 6) {
                    value("editor.name", node.name)
                    if let url = node.url { value("editor.url", url) }
                    value("editor.folder", node.parent.map { tree.path(to: $0) } ?? L("review.root"))
                    if node.isFolder {
                        Text("review.childOrder").foregroundStyle(.secondary)
                        if node.children.isEmpty { Text("review.emptyFolder").foregroundStyle(.secondary) }
                        ForEach(Array(node.children.enumerated()), id: \.element) { index, childID in
                            if let child = tree.nodes[childID] {
                                Text(verbatim: "\(index + 1). \(child.name)")
                                if let url = child.url { Text(verbatim: url).foregroundStyle(.secondary) }
                            }
                        }
                    }
                        DisclosureGroup("review.metadata") {
                            value("review.identity", node.id)
                            ForEach(node.metadata.keys.sorted(), id: \.self) { key in
                                Text(verbatim: key + ": " + (node.metadata[key]?.display ?? ""))
                            }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.caption).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func value(_ key: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L(key)).foregroundStyle(.secondary)
            Text(verbatim: content)
        }
    }
}

struct ChangeReviewList: View {
    let before: BookmarkTree
    let after: BookmarkTree

    private var ids: [String] {
        Set(before.nodes.keys).union(after.nodes.keys).filter { before.nodes[$0] != after.nodes[$0] }.sorted()
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            let removedCount = Set(before.nodes.keys).subtracting(after.nodes.keys).count
            if removedCount > 0 { Text(localizedCount("review.removalCount", removedCount)).foregroundStyle(.orange) }
            ForEach(ids, id: \.self) { id in
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text((after.nodes[id] ?? before.nodes[id])?.name ?? "").font(.headline)
                        if before.nodes[id] == nil { Label("change.added", systemImage: "plus.circle").foregroundStyle(AppTheme.accent) }
                        else if after.nodes[id] == nil { Label("change.removed", systemImage: "minus.circle").foregroundStyle(.orange) }
                        else if before.nodes[id]?.children != after.nodes[id]?.children { Label("change.contents", systemImage: "folder").foregroundStyle(.blue) }
                        else { Label("change.edited", systemImage: "pencil").foregroundStyle(.blue) }
                        if before.nodes[id] != nil {
                            Text("review.before").font(.subheadline.bold())
                            BookmarkSnapshot(tree: before, id: id)
                        }
                        if after.nodes[id] != nil {
                            Text("review.after").font(.subheadline.bold())
                            BookmarkSnapshot(tree: after, id: id)
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if ids.isEmpty { Text("review.noRemainingChanges").foregroundStyle(.secondary) }
        }
    }
}
