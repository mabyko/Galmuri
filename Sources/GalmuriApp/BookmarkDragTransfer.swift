import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let galmuriBookmarkMove = UTType(exportedAs: "app.galmuri.bookmark-move", conformingTo: .data)
}

struct BookmarkMoveData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .galmuriBookmarkMove) { $0.data } importing: { Self(data: $0) }
    }
}

struct BookmarkFolderDropTarget: ViewModifier {
    let move: ([BookmarkMoveData]) -> Bool
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(targeted ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4))
            .dropDestination(for: BookmarkMoveData.self) { items, _ in move(items) } isTargeted: { targeted = $0 }
    }
}
