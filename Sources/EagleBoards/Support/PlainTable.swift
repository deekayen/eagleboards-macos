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
    /// The order, by a column's ID. A click on a heading sets it, as View ›
    /// Sort By does.
    @Binding var sort: TableSort
    let name: String
    @Binding var selection: Set<String>
    var doubleClick: ((String) -> Void)?
    var menuItems: [PlainMenuItem] = []
    /// Take the focus as the page is shown, if nothing else has it.
    var takesFocus = false
    /// Changed by Return in the toolbar search: the first row is selected,
    /// scrolled to and focused.
    var firstRowRequest = 0

    func makeCoordinator() -> PlainTableCoordinator { PlainTableCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = PageTableView()
        table.takesFocusWhenShown = takesFocus
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
        table.sortDescriptors = [NSSortDescriptor(key: sort.column, ascending: sort.ascending)]
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
        // A search submitted before the page was shown is not this page's.
        context.coordinator.firstRowRequest = firstRowRequest
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
                order: $sort,
                doubleClick: doubleClick,
                menuItems: menuItems,
                firstRowRequest: firstRowRequest
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
    /// What the column sorts by when it shows something else: a date in
    /// words sorts by its `2026-08-25` stamp.
    var sortText: ((Row) -> String)?

    func compare(_ a: Row, _ b: Row) -> ComparisonResult {
        if let sortKey {
            let (left, right) = (sortKey(a), sortKey(b))
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        }
        let key = sortText ?? text
        return key(a).localizedStandardCompare(key(b))
    }

    func cell(_ row: Row) -> PlainCell.Content {
        PlainCell.Content(text: text(row), style: style, toolTip: toolTip(row), checked: checked(row))
    }

    /// The column as View › Sort By lists it.
    var sortColumn: SortColumn { SortColumn(id: id, title: title, ascendingFirst: ascendingFirst) }
}

/// The table a page shows. It takes the focus once, as the page is shown,
/// when nothing else has it (Windows' FocusPage): focus left in the toolbar
/// search stays there.
final class PageTableView: NSTableView {
    var takesFocusWhenShown = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard takesFocusWhenShown, window != nil else { return }
        takesFocusWhenShown = false
        // A turn later, once the page it replaces has left the window and
        // let go of the focus.
        Task { [weak self] in
            guard let self, let window = self.window,
                  window.firstResponder == nil || window.firstResponder === window
            else { return }
            window.makeFirstResponder(self)
        }
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
        /// The order the page keeps, which the headings show.
        let order: Binding<TableSort>
        let doubleClick: ((String) -> Void)?
        let menuItems: [PlainMenuItem]
        let firstRowRequest: Int
    }

    weak var table: NSTableView?
    private var model: Model?
    private(set) var shownRows: Any?
    private var sorted: [String] = []
    private var isApplyingSelection = false
    private var isApplyingSort = false
    /// The last Return in the search this table has gone to the first row for.
    var firstRowRequest = 0

    /// Re-sort and redraw only when the rows or their order changed: SwiftUI
    /// asks after every change to the event.
    func update(_ model: Model, rows: Any) {
        let changed = shownRows == nil || model.changed()
        self.model = model
        let reordered = applySort(model.order.wrappedValue)
        if changed {
            shownRows = rows
        }
        if changed || reordered {
            resort()
        }
        applySelection()
        if model.firstRowRequest != firstRowRequest {
            firstRowRequest = model.firstRowRequest
            // Not while SwiftUI is updating the view: selecting reports the
            // selection back to it.
            Task { [weak self] in self?.goToFirstRow() }
        }
    }

    /// View › Sort By's order onto the headings. True when it changed them.
    private func applySort(_ sort: TableSort) -> Bool {
        guard let table else { return false }
        let shown = table.sortDescriptors.first
        guard shown?.key != sort.column || shown?.ascending != sort.ascending else { return false }
        isApplyingSort = true
        table.sortDescriptors = [NSSortDescriptor(key: sort.column, ascending: sort.ascending)]
        isApplyingSort = false
        return true
    }

    /// Return in the search: the first row found, selected, in view and
    /// with the focus.
    private func goToFirstRow() {
        guard let table, !sorted.isEmpty else { return }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.scrollRowToVisible(0)
        table.window?.makeFirstResponder(table)
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
        // View › Sort By's own change, which `update` sorts by.
        guard !isApplyingSort else { return }
        resort()
        applySelection()
        // A click on a heading, for View › Sort By's checks.
        if let model, let shown = tableView.sortDescriptors.first, let key = shown.key {
            let sort = TableSort(key, ascending: shown.ascending)
            if model.order.wrappedValue != sort { model.order.wrappedValue = sort }
        }
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
        /// A board role: Chair in semibold, and Unavailable as the role
        /// menus say it, No Thanks.
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
        // A value cut off shows in full on hover, as in Mac tables, except
        // in a column with its own tooltip (Notes), which already shows the
        // whole value: the expanded copy would cover it.
        label.allowsExpansionToolTips = content.toolTip == nil
        let body = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        switch (content.style, BoardRole(rawValue: content.text)) {
        case (.role, .chair):
            label.attributedStringValue = NSAttributedString(string: "Chair", attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ])
        case (.role, .unavailable):
            label.attributedStringValue = NSAttributedString(string: "No Thanks", attributes: [
                .font: body, .foregroundColor: NSColor.secondaryLabelColor,
            ])
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
