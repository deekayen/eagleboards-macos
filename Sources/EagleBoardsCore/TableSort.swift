/// How a table page is sorted: by which column, and which way. A click on a
/// column heading and View › Sort By both set it, so the menu can sort a
/// table from the keyboard, which cannot reach the headings.
public struct TableSort: Hashable, Sendable {
    /// The column's ID, as the page names it.
    public var column: String
    public var ascending: Bool

    public init(_ column: String, ascending: Bool = true) {
        self.column = column
        self.ascending = ascending
    }

    /// View › Sort By's choice of `column`. The column already sorted by
    /// keeps its order; another starts the way a click on its heading would,
    /// ascending unless the column lists its newest first (`ascendingFirst`).
    public func sorting(by column: String, ascendingFirst: Bool = true) -> TableSort {
        column == self.column ? self : TableSort(column, ascending: ascendingFirst)
    }
}
