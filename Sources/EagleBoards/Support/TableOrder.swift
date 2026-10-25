import EagleBoardsCore
import SwiftUI

/// A column View › Sort By offers, under the heading the page shows.
struct SortColumn: Identifiable {
    let id: String
    let title: String
    /// False for a column that lists the newest first, as a click on its
    /// heading does.
    var ascendingFirst = true
}

/// A SwiftUI table page's sortable columns, in the table's order, with the
/// comparators their headings sort by, so that the page's order lives in the
/// model, where View › Sort By reaches it. A column's heading is its ID.
struct TableOrder<Row> {
    struct Column {
        let title: String
        let comparator: KeyPathComparator<Row>

        /// Text, compared as a String column's heading compares it, the way
        /// the Finder sorts names.
        init(_ title: String, _ keyPath: any KeyPath<Row, String> & Sendable) {
            self.title = title
            comparator = KeyPathComparator(keyPath, comparator: .localizedStandard)
        }

        init<Value: Comparable>(_ title: String, _ keyPath: any KeyPath<Row, Value> & Sendable) {
            self.title = title
            comparator = KeyPathComparator(keyPath)
        }
    }

    let columns: [Column]

    init(_ columns: [Column]) {
        self.columns = columns
    }

    var sortColumns: [SortColumn] { columns.map { SortColumn(id: $0.title, title: $0.title) } }

    /// What the table sorts by for `sort`: the first column when `sort`
    /// names none of them.
    func comparators(for sort: TableSort) -> [KeyPathComparator<Row>] {
        guard var comparator = (columns.first { $0.title == sort.column } ?? columns.first)?.comparator else { return [] }
        comparator.order = sort.ascending ? .forward : .reverse
        return [comparator]
    }

    /// The order a click on a heading asks for, found by the key path its
    /// column sorts on.
    func sort(from comparators: [KeyPathComparator<Row>]) -> TableSort? {
        guard let first = comparators.first,
              let column = columns.first(where: { $0.comparator.keyPath == first.keyPath })
        else { return nil }
        return TableSort(column.title, ascending: first.order == .forward)
    }
}

extension AppModel {
    /// A table's `sortOrder`, read from and written to the page's order.
    func sortOrder<Row>(for page: Page, _ order: TableOrder<Row>) -> Binding<[KeyPathComparator<Row>]> {
        Binding(
            get: { order.comparators(for: self.sort(for: page)) },
            set: { if let sort = order.sort(from: $0) { self.setSort(sort, for: page) } }
        )
    }
}

extension AppModel.Page {
    /// The order a page opens in: the Results and Youth pages in sign-in
    /// order, the rest by name.
    var defaultSort: TableSort {
        switch self {
        case .event: TableSort("")
        case .results, .youth: TableSort("Sign-In Number")
        case .adults, .preRegistered: TableSort("Last Name")
        case .rooms: TableSort("Room")
        case .adultHistory, .approvedProposals: TableSort("last")
        }
    }

    /// The columns View › Sort By lists for the page. None on the Event page.
    @MainActor
    var sortColumns: [SortColumn] {
        switch self {
        case .event: []
        case .results: ResultsPage.order.sortColumns
        case .adults: AdultList.order.sortColumns
        case .youth: YouthPage.order.sortColumns
        case .preRegistered: PreRegisteredPage.order.sortColumns
        case .adultHistory: AdultHistoryPage.sortColumns
        case .rooms: RoomsPage.order.sortColumns
        case .approvedProposals: ApprovedProposalsPage.sortColumns
        }
    }
}

/// View › Sort By: the page's columns, with a check on the one it is sorted
/// by, then which way. The same as a click on a column heading, which the
/// keyboard cannot reach. Dimmed on the Event page, which has no table.
struct SortByMenu: View {
    let model: AppModel

    var body: some View {
        let page = model.page
        let columns = model.event == nil ? [] : page.sortColumns
        let sort = model.sort(for: page)
        Menu("Sort By") {
            ForEach(columns) { column in
                Toggle(column.title, isOn: Binding(
                    get: { sort.column == column.id },
                    set: { _ in model.setSort(sort.sorting(by: column.id, ascendingFirst: column.ascendingFirst), for: page) }
                ))
            }
            Divider()
            Toggle("Ascending", isOn: Binding(
                get: { sort.ascending },
                set: { _ in model.setSort(TableSort(sort.column, ascending: true), for: page) }
            ))
            Toggle("Descending", isOn: Binding(
                get: { !sort.ascending },
                set: { _ in model.setSort(TableSort(sort.column, ascending: false), for: page) }
            ))
        }
        .disabled(columns.isEmpty)
    }
}
