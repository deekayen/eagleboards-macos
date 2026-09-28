import AppKit
import EagleBoardsCore
import SwiftUI

/// A read-only table in plain AppKit, for the pages that can run to thousands
/// of rows: the Adult History CSV and Approved Proposals.
///
/// A SwiftUI `Table` gives every cell a hosting view of its own, and each of
/// those stops observing the window as the table leaves it. Scrolled from top
/// to bottom, a long table left thousands of them, and taking it off the
/// window (switching to another page) took seconds to minutes, since each
/// removal copies the window's list of observers: the app froze. Here the
/// cells are text fields the table reuses as it scrolls.
struct PlainTable<Row: Identifiable & Equatable>: NSViewRepresentable where Row.ID == String {
    let rows: [Row]
    let columns: [PlainColumn<Row>]
    /// The column sorted by at first, ascending.
    let sortedBy: String
    let name: String
    @Binding var selection: Set<String>
    var doubleClick: ((String) -> Void)?
    var menuItems: [PlainMenuItem] = []

    func makeCoordinator() -> PlainTableCoordinator { PlainTableCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 40
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.id, ascending: column.ascendingFirst)
            table.addTableColumn(tableColumn)
        }
        table.sortDescriptors = [NSSortDescriptor(key: sortedBy, ascending: true)]
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(PlainTableCoordinator.doubleClicked(_:))
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        table.setAccessibilityLabel(name)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let columns = columns
        let rows = rows
        context.coordinator.update(
            PlainTableCoordinator.Model(
                rowsKey: rows.map(\.id),
                changed: { [previous = context.coordinator.shownRows as? [Row]] in previous != rows },
                sort: { columnID, ascending in
                    guard let column = columns.first(where: { $0.id == columnID }) else { return rows.map(\.id) }
                    return rows.sorted { a, b in
                        let order = column.compare(a, b)
                        return order == .orderedSame ? false : (order == .orderedAscending) == ascending
                    }.map(\.id)
                },
                cell: { id, columnID in
                    guard let row = byID[id], let column = columns.first(where: { $0.id == columnID }) else { return nil }
                    return column.cell(row)
                },
                selection: $selection,
                doubleClick: doubleClick,
                menuItems: menuItems
            ),
            rows: rows
        )
    }
}

/// One column of a `PlainTable`: its title, width, and how a row reads in it.
struct PlainColumn<Row> {
    let id: String
    let title: String
    var width: CGFloat = 120
    var style: PlainCell.Style = .plain
    var ascendingFirst = true
    let text: (Row) -> String
    var toolTip: (Row) -> String? = { _ in nil }
    var checked: (Row) -> Bool = { _ in false }
    var sortKey: ((Row) -> Int)?

    func compare(_ a: Row, _ b: Row) -> ComparisonResult {
        if let sortKey {
            let (left, right) = (sortKey(a), sortKey(b))
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        }
        return text(a).localizedStandardCompare(text(b))
    }

    func cell(_ row: Row) -> PlainCell.Content {
        PlainCell.Content(text: text(row), style: style, toolTip: toolTip(row), checked: checked(row))
    }
}

/// A right-click menu command on the selected (or clicked) rows.
struct PlainMenuItem {
    let title: String
    let isEnabled: (Set<String>) -> Bool
    let action: (Set<String>) -> Void
}

/// The table's data source and delegate. Not generic, so AppKit can call its
/// selectors: `PlainTable` hands it the rows as closures.
@MainActor
final class PlainTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    struct Model {
        let rowsKey: [String]
        let changed: () -> Bool
        let sort: (String, Bool) -> [String]
        let cell: (String, String) -> PlainCell.Content?
        let selection: Binding<Set<String>>
        let doubleClick: ((String) -> Void)?
        let menuItems: [PlainMenuItem]
    }

    weak var table: NSTableView?
    private var model: Model?
    private(set) var shownRows: Any?
    private var sorted: [String] = []
    private var isApplyingSelection = false

    /// Re-sort and redraw only when the rows changed: SwiftUI asks after
    /// every change to the event.
    func update(_ model: Model, rows: Any) {
        let changed = shownRows == nil || model.changed()
        self.model = model
        if changed {
            shownRows = rows
            resort()
        }
        applySelection()
    }

    private func resort() {
        guard let model else { return }
        let descriptor = table?.sortDescriptors.first
        sorted = model.sort(descriptor?.key ?? "", descriptor?.ascending ?? true)
        table?.reloadData()
    }

    private func applySelection() {
        guard let table, let model else { return }
        let wanted = IndexSet(sorted.indices.filter { model.selection.wrappedValue.contains(sorted[$0]) })
        guard wanted != table.selectedRowIndexes else { return }
        isApplyingSelection = true
        table.selectRowIndexes(wanted, byExtendingSelection: false)
        isApplyingSelection = false
    }

    private var clickedIDs: Set<String> {
        guard let table else { return [] }
        let rows = table.clickedRow >= 0 && !table.selectedRowIndexes.contains(table.clickedRow)
            ? IndexSet(integer: table.clickedRow)
            : table.selectedRowIndexes
        return Set(rows.compactMap { $0 < sorted.count ? sorted[$0] : nil })
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sorted.count }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        resort()
        applySelection()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection, let table, let model else { return }
        model.selection.wrappedValue = Set(table.selectedRowIndexes.compactMap { $0 < sorted.count ? sorted[$0] : nil })
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < sorted.count, let content = model?.cell(sorted[row], tableColumn.identifier.rawValue) else {
            return nil
        }
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? PlainCell
            ?? PlainCell(identifier: tableColumn.identifier)
        cell.show(content)
        return cell
    }

    @objc func doubleClicked(_ sender: NSTableView) {
        guard sender.clickedRow >= 0, sender.clickedRow < sorted.count else { return }
        model?.doubleClick?(sorted[sender.clickedRow])
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let ids = clickedIDs
        guard !ids.isEmpty, let model else { return }
        for (index, command) in model.menuItems.enumerated() {
            let item = NSMenuItem(title: command.title, action: #selector(menuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = Array(ids)
            item.isEnabled = command.isEnabled(ids)
            menu.addItem(item)
        }
    }

    @objc private func menuChosen(_ sender: NSMenuItem) {
        guard let model, sender.tag < model.menuItems.count else { return }
        model.menuItems[sender.tag].action(Set((sender.representedObject as? [String]) ?? []))
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool { item.isEnabled }
}

/// One cell of a `PlainTable`: a label, and a check when the row has one.
final class PlainCell: NSTableCellView {
    enum Style {
        case plain
        case digits
        /// A board role: Chair marked, "No thanks" as a dash.
        case role
    }

    struct Content {
        let text: String
        let style: Style
        let toolTip: String?
        let checked: Bool
    }

    private let label = NSTextField(labelWithString: "")
    private let check = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Signed in today")
        check.contentTintColor = .controlAccentColor
        check.toolTip = "Signed in today"
        let stack = NSStackView(views: [label, check])
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        textField = label
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func show(_ content: Content) {
        check.isHidden = !content.checked
        toolTip = content.toolTip
        let body = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        switch (content.style, BoardRole(rawValue: content.text)) {
        case (.role, .chair):
            label.attributedStringValue = NSAttributedString(string: "Chair", attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
            ])
        case (.role, .unavailable):
            label.attributedStringValue = NSAttributedString(string: "—", attributes: [
                .font: body, .foregroundColor: NSColor.secondaryLabelColor,
            ])
            toolTip = "No thanks"
        case (.digits, _):
            label.attributedStringValue = NSAttributedString(string: content.text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ])
        default:
            label.attributedStringValue = NSAttributedString(string: content.text, attributes: [
                .font: body, .foregroundColor: NSColor.labelColor,
            ])
        }
    }
}

extension Adult {
    /// The last event they signed in at, from `(2026-08-25)(2026-09-22)`.
    var lastEvent: String {
        boardHistory.split(separator: ")").last.map { $0.trimmingCharacters(in: ["("]) } ?? ""
    }

    var eventCount: Int { boardHistory.filter { $0 == "(" }.count }
}
