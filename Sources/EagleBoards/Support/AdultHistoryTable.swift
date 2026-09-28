import AppKit
import EagleBoardsCore
import SwiftUI

/// The Adult History CSV as a plain AppKit table: read-only, and thousands of
/// rows long in a district that has run for years.
///
/// A SwiftUI `Table` gives every cell a hosting view of its own, and each of
/// those stops observing the window when the table leaves it. Scrolled from
/// top to bottom, the history left thousands of them, and taking it off the
/// window (switching to another page) took seconds to minutes, since each
/// removal copies the window's list of observers: the app froze. Here the
/// cells are text fields the table reuses as it scrolls.
struct AdultHistoryTable: NSViewRepresentable {
    let rows: [Adult]
    let signedIn: Set<Adult.ID>
    @Binding var selection: Set<Adult.ID>
    let signIn: (Set<Adult.ID>) -> Void

    enum Column: String, CaseIterable {
        case lastEvent, last, first, unit, finalBoard, projectReview, events, email, phone

        var title: String {
            switch self {
            case .lastEvent: "Last Event"
            case .last: "Last"
            case .first: "First"
            case .unit: "Unit"
            case .finalBoard: "Final"
            case .projectReview: "Project"
            case .events: "Events"
            case .email: "Email"
            case .phone: "Phone"
            }
        }

        var width: CGFloat {
            switch self {
            case .lastEvent: 110
            case .last, .first: 130
            case .unit: 90
            case .finalBoard, .projectReview: 70
            case .events: 55
            case .email: 220
            case .phone: 120
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 40
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: column != .lastEvent)
            table.addTableColumn(tableColumn)
        }
        table.sortDescriptors = [NSSortDescriptor(key: Column.last.rawValue, ascending: true)]
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        table.setAccessibilityLabel("Adult History CSV")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: AdultHistoryTable
        weak var table: NSTableView?
        private var sorted: [Adult] = []
        private var shownRows: [Adult] = []
        private var shownSignedIn: Set<Adult.ID> = []
        private var isApplyingSelection = false

        init(_ parent: AdultHistoryTable) {
            self.parent = parent
        }

        /// Re-sort and redraw only when the rows or who is signed in changed:
        /// SwiftUI asks after every change to the event.
        func update(_ parent: AdultHistoryTable) {
            self.parent = parent
            if parent.rows != shownRows || parent.signedIn != shownSignedIn {
                shownRows = parent.rows
                shownSignedIn = parent.signedIn
                resort()
            }
            applySelection()
        }

        private func resort() {
            let descriptor = table?.sortDescriptors.first
            let column = descriptor.flatMap { Column(rawValue: $0.key ?? "") } ?? .last
            let ascending = descriptor?.ascending ?? true
            sorted = shownRows.sorted { a, b in
                let order = Self.compare(a, b, by: column)
                return order == .orderedSame ? a.last < b.last : (order == .orderedAscending) == ascending
            }
            table?.reloadData()
        }

        private static func compare(_ a: Adult, _ b: Adult, by column: Column) -> ComparisonResult {
            switch column {
            case .events: return eventCount(a) == eventCount(b) ? .orderedSame : (eventCount(a) < eventCount(b) ? .orderedAscending : .orderedDescending)
            default: return text(a, column).localizedStandardCompare(text(b, column))
            }
        }

        private static func eventCount(_ adult: Adult) -> Int {
            adult.boardHistory.filter { $0 == "(" }.count
        }

        static func text(_ adult: Adult, _ column: Column) -> String {
            switch column {
            case .lastEvent: adult.lastEvent
            case .last: adult.last
            case .first: adult.first
            case .unit: adult.unitDisplay
            case .finalBoard: adult.finalBoardRoleText
            case .projectReview: adult.projectReviewRoleText
            case .events: "\(eventCount(adult))"
            case .email: adult.email
            case .phone: adult.phone
            }
        }

        private func applySelection() {
            guard let table else { return }
            let wanted = IndexSet(sorted.indices.filter { parent.selection.contains(sorted[$0].id) })
            guard wanted != table.selectedRowIndexes else { return }
            isApplyingSelection = true
            table.selectRowIndexes(wanted, byExtendingSelection: false)
            isApplyingSelection = false
        }

        private var clickedIDs: Set<Adult.ID> {
            guard let table else { return [] }
            let rows = table.clickedRow >= 0 && !table.selectedRowIndexes.contains(table.clickedRow)
                ? IndexSet(integer: table.clickedRow)
                : table.selectedRowIndexes
            return Set(rows.compactMap { $0 < sorted.count ? sorted[$0].id : nil })
        }

        // MARK: Data source and delegate

        func numberOfRows(in tableView: NSTableView) -> Int { sorted.count }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            resort()
            applySelection()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection, let table else { return }
            parent.selection = Set(table.selectedRowIndexes.compactMap { $0 < sorted.count ? sorted[$0].id : nil })
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue), row < sorted.count else {
                return nil
            }
            let adult = sorted[row]
            let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? HistoryCell
                ?? HistoryCell(identifier: tableColumn.identifier)
            cell.show(adult, column, signedIn: parent.signedIn.contains(adult.id))
            return cell
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            guard sender.clickedRow >= 0, sender.clickedRow < sorted.count else { return }
            let id = sorted[sender.clickedRow].id
            if !parent.signedIn.contains(id) { parent.signIn([id]) }
        }

        // MARK: The right-click menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let ids = clickedIDs
            guard !ids.isEmpty else { return }
            let item = NSMenuItem(title: "Sign In for Today", action: #selector(signInClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Array(ids)
            item.isEnabled = !ids.isSubset(of: parent.signedIn)
            menu.addItem(item)
        }

        @objc private func signInClicked(_ sender: NSMenuItem) {
            let ids = Set((sender.representedObject as? [Adult.ID]) ?? [])
            parent.signIn(ids.subtracting(parent.signedIn))
        }

        func validateMenuItem(_ item: NSMenuItem) -> Bool { item.isEnabled }
    }
}

/// One cell of the history table: a label, and for Last Event a check for
/// someone signed in today.
private final class HistoryCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let check = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        check.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Signed in today")
        check.contentTintColor = .controlAccentColor
        check.toolTip = "Signed in today"
        check.translatesAutoresizingMaskIntoConstraints = false
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

    func show(_ adult: Adult, _ column: AdultHistoryTable.Column, signedIn: Bool) {
        let text = AdultHistoryTable.Coordinator.text(adult, column)
        check.isHidden = !(column == .lastEvent && signedIn)
        toolTip = column == .events ? adult.boardHistory : nil
        switch column {
        case .finalBoard, .projectReview:
            switch BoardRole(rawValue: text) {
            case .chair:
                label.attributedStringValue = NSAttributedString(string: "Chair", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                    .foregroundColor: NSColor.controlAccentColor,
                ])
            case .unavailable:
                label.attributedStringValue = NSAttributedString(string: "—", attributes: [.foregroundColor: NSColor.secondaryLabelColor])
                toolTip = "No thanks"
            default:
                label.stringValue = text
                label.textColor = .labelColor
                label.font = .systemFont(ofSize: NSFont.systemFontSize)
            }
        case .lastEvent, .events:
            label.stringValue = text
            label.textColor = .labelColor
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        default:
            label.stringValue = text
            label.textColor = .labelColor
            label.font = .systemFont(ofSize: NSFont.systemFontSize)
        }
    }
}

extension Adult {
    /// The last event they signed in at, from `(2026-08-25)(2026-09-22)`.
    var lastEvent: String {
        boardHistory.split(separator: ")").last.map { $0.trimmingCharacters(in: ["("]) } ?? ""
    }
}
