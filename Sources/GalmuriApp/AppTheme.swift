import AppKit
import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.32, green: 0.56, blue: 0.94)
    static let selection = Color(red: 0.18, green: 0.27, blue: 0.41)
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let inset = Color.primary.opacity(0.035)
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fontWeight(.medium).padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .background(enabled ? AppTheme.accent.opacity(configuration.isPressed ? 0.7 : 1) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }
}

// Only Galmuri's own native tables are styled; input and selection remain native.
@MainActor private final class TableSelectionAppearance: NSObject {
    weak var table: NSTableView?
    init(table: NSTableView) {
        self.table = table; super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSTableView.selectionDidChangeNotification, object: table)
    }
    func paint(_ row: NSTableRowView) {
        guard let table else { return }
        let index = table.row(for: row)
        let color = index >= 0 && table.isRowSelected(index) ? NSColor(AppTheme.selection) : .clear
        if row.backgroundColor != color { row.backgroundColor = color }
    }
    @objc private func refresh() {
        guard let table else { return }
        let visible = table.rows(in: table.visibleRect)
        guard visible.location != NSNotFound else { return }
        for index in visible.location..<(visible.location + visible.length) {
            if let row = table.rowView(atRow: index, makeIfNecessary: false) { paint(row) }
        }
    }
}
private final class TableCellBackground: NSView {
    private static let appearances = NSMapTable<NSTableView, TableSelectionAppearance>.weakToStrongObjects()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configureRow() }
    func configureRow() {
        var parent = superview, row: NSTableRowView?
        while let view = parent {
            if let candidate = view as? NSTableRowView { row = candidate }
            if let table = view as? NSTableView {
                if table.selectionHighlightStyle != .none { table.selectionHighlightStyle = .none }
                let appearance: TableSelectionAppearance
                if let existing = Self.appearances.object(forKey: table) { appearance = existing }
                else { appearance = TableSelectionAppearance(table: table); Self.appearances.setObject(appearance, forKey: table) }
                if let row { appearance.paint(row) }
                break
            }
            parent = view.superview
        }
    }
}
private struct NativeSelectionBackground: NSViewRepresentable {
    let selected: Bool
    func makeNSView(context: Context) -> NSView { TableCellBackground() }
    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? TableCellBackground else { return }
        view.configureRow()
    }
}
struct AppTableCell: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(NativeSelectionBackground(selected: selected))
    }
}
