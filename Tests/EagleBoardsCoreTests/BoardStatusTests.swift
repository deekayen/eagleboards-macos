import EagleBoardsCore
import Testing

/// The questions the menus and the lists ask of a status, answered once in
/// `BoardStatus` so no page spells them out again.
@Suite("Board status questions")
struct BoardStatusTests {
    @Test(arguments: [
        (BoardStatus.registered, false), (.verified, false), (.seated, true),
        (.inProgress, true), (.completed, false), (.postponed, false),
    ])
    func onlyASittingBoardHoldsARoom(status: BoardStatus, holds: Bool) {
        #expect(status.holdsRoom == holds)
    }

    @Test(arguments: [
        (BoardStatus.registered, false), (.verified, true), (.seated, true),
        (.inProgress, true), (.completed, false), (.postponed, false),
    ])
    func resetBoardTakesASittingBoardAndTheLegacyVerifiedStatus(status: BoardStatus, resettable: Bool) {
        #expect(status.isResettable == resettable)
    }
}
