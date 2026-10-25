/// The arithmetic behind the arrow keys on the Event page's room cards, which
/// an adaptive grid lays out in rows as wide as the window allows. It is here
/// rather than in the view so it can be tested.
public enum CardGrid {
    public enum Move: Sendable {
        case left, right, up, down
    }

    /// How many cards fit across `width`: as many of at least `minimum`
    /// points, with `spacing` between them, as it holds, and never fewer
    /// than one. This is how an adaptive grid column lays them out.
    public static func columns(width: Double, minimum: Double, spacing: Double) -> Int {
        guard minimum + spacing > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
    }

    /// Where an arrow key takes the selection from the card at `index`, of
    /// `count` laid out `columns` across. Left and right step through the
    /// cards in reading order, from the end of one row to the start of the
    /// next; up and down move a row, and down lands on the last card when the
    /// row below is shorter. Nil when the selection stays where it is, at an
    /// edge.
    public static func index(after move: Move, from index: Int, count: Int, columns: Int) -> Int? {
        guard (0..<count).contains(index) else { return nil }
        let columns = max(1, columns)
        let target: Int
        switch move {
        case .left:
            target = index - 1
        case .right:
            target = index + 1
        case .up:
            target = index - columns
        case .down:
            guard index / columns < (count - 1) / columns else { return nil }
            target = min(index + columns, count - 1)
        }
        return (0..<count).contains(target) ? target : nil
    }
}
