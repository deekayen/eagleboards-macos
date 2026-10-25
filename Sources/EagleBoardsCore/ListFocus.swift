/// Where the keyboard focus goes when the row holding it leaves a list: the
/// inspector's board and free adults, and Change Members' two lists, whose
/// rows go as adults are added, taken off, or proposed afresh. Windows' Event
/// page does the same (RestoreFocus). It is here rather than in the views so
/// it can be tested.
public enum ListFocus {
    /// The row to focus once the list goes from `old` to `new`, if `focused`
    /// had the focus: the same row while it is still there; else the row
    /// now in its place, or the last row when it was at the end. Nil when the
    /// list is left empty, or `focused` was not in it, for the find field
    /// above the list to take the focus instead.
    public static func row<ID: Equatable>(_ focused: ID, in old: [ID], becoming new: [ID]) -> ID? {
        if new.contains(focused) { return focused }
        guard let index = old.firstIndex(of: focused), !new.isEmpty else { return nil }
        return new[min(index, new.count - 1)]
    }

    /// The same for a row about to leave `rows` by the button that has the
    /// focus: the next row, or the one before it at the end of the list.
    public static func row<ID: Equatable>(after leaving: ID, in rows: [ID]) -> ID? {
        row(leaving, in: rows, becoming: rows.filter { $0 != leaving })
    }
}
