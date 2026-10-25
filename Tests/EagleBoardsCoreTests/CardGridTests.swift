import EagleBoardsCore
import Testing

/// The room cards' arrow keys: ten cards, three across, in rows of 3, 3, 3
/// and 1.
@Suite("Arrow keys on the room cards")
struct CardGridTests {
    private func move(_ move: CardGrid.Move, from index: Int, count: Int = 10, columns: Int = 3) -> Int? {
        CardGrid.index(after: move, from: index, count: count, columns: columns)
    }

    @Test func columnsAreAsManyAsTheWidthHoldsAndAtLeastOne() {
        // The Event page's cards: at least 220 points, 10 apart.
        #expect(CardGrid.columns(width: 219, minimum: 220, spacing: 10) == 1)
        #expect(CardGrid.columns(width: 449, minimum: 220, spacing: 10) == 1)
        #expect(CardGrid.columns(width: 450, minimum: 220, spacing: 10) == 2)
        #expect(CardGrid.columns(width: 680, minimum: 220, spacing: 10) == 3)
        #expect(CardGrid.columns(width: 0, minimum: 220, spacing: 10) == 1)
    }

    @Test func leftAndRightStepThroughTheCardsAcrossTheEndsOfRows() {
        #expect(move(.right, from: 0) == 1)
        #expect(move(.right, from: 2) == 3)
        #expect(move(.left, from: 3) == 2)
        #expect(move(.left, from: 0) == nil)
        #expect(move(.right, from: 9) == nil)
    }

    @Test func upAndDownMoveARow() {
        #expect(move(.down, from: 1) == 4)
        #expect(move(.up, from: 4) == 1)
        #expect(move(.up, from: 2) == nil)
        #expect(move(.down, from: 9) == nil)
    }

    @Test func downOntoAShorterRowLandsOnTheLastCard() {
        #expect(move(.down, from: 6) == 9)
        #expect(move(.down, from: 8) == 9)
    }

    @Test func oneColumnMovesOneCardAtATime() {
        #expect(move(.down, from: 0, count: 3, columns: 1) == 1)
        #expect(move(.up, from: 2, count: 3, columns: 1) == 1)
        #expect(move(.down, from: 2, count: 3, columns: 1) == nil)
        // A width that fits no card still lays them out one across.
        #expect(move(.down, from: 0, count: 3, columns: 0) == 1)
    }

    @Test func aCardNoLongerShownMovesNothing() {
        #expect(move(.right, from: 10) == nil)
        #expect(move(.down, from: 0, count: 0) == nil)
    }
}
