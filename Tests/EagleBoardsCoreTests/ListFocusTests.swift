import EagleBoardsCore
import Testing

/// The inspector's and Change Members' lists: the focus stays on the row it
/// was on, or moves to the row now in its place, never to nowhere.
@Suite("Keyboard focus when a row leaves a list")
struct ListFocusTests {
    @Test func aRowStillThereKeepsTheFocus() {
        // Someone signing in adds a row above it.
        #expect(ListFocus.row("b", in: ["a", "b", "c"], becoming: ["new", "a", "b", "c"]) == "b")
    }

    @Test func aRowThatLeavesHandsTheFocusToTheRowNowInItsPlace() {
        #expect(ListFocus.row("b", in: ["a", "b", "c"], becoming: ["a", "c"]) == "c")
        #expect(ListFocus.row("a", in: ["a", "b", "c"], becoming: ["b", "c"]) == "b")
    }

    @Test func theLastRowLeavingHandsTheFocusToTheOneBeforeIt() {
        #expect(ListFocus.row("c", in: ["a", "b", "c"], becoming: ["a", "b"]) == "b")
        // A refresh that takes several rows at once, the focused one among them.
        #expect(ListFocus.row("c", in: ["a", "b", "c", "d"], becoming: ["a"]) == "a")
    }

    @Test func anEmptiedListLeavesTheFocusToTheFindField() {
        #expect(ListFocus.row("a", in: ["a"], becoming: []) == nil)
        #expect(ListFocus.row("x", in: ["a", "b"], becoming: ["a"]) == nil)
    }

    @Test func aButtonThatTakesItsRowAwayFocusesTheNextRow() {
        // + puts an adult on the board, and focus goes to the next adult's +.
        #expect(ListFocus.row(after: "b", in: ["a", "b", "c"]) == "c")
        #expect(ListFocus.row(after: "c", in: ["a", "b", "c"]) == "b")
        #expect(ListFocus.row(after: "a", in: ["a"]) == nil)
    }
}
