import EagleBoardsCore
import Testing

/// What each page of the scheduler has in view, which decides what a command
/// and the inspector may act on: the board only where the inspector is, rooms
/// only where they are listed, adults only where they are listed.
@Suite("What a scheduler page shows")
struct SchedulerPageTests {
    @Test func theViewMenuListsTheEightPagesInOrder() {
        // Command-1 to Command-8 follow this order (SPEC.md P-3, P-6).
        #expect(SchedulerPage.allCases == [
            .event, .results, .adults, .youth, .preRegistered, .adultHistory, .rooms, .approvedProposals,
        ])
    }

    @Test func onlyTheEventPageShowsTheSelectedYouthsBoard() {
        #expect(SchedulerPage.allCases.filter(\.showsBoard) == [.event])
    }

    @Test func theEventPageAndTheRoomsPageShowRooms() {
        #expect(SchedulerPage.allCases.filter(\.showsRooms) == [.event, .rooms])
    }

    @Test func onlyTheAdultsPageListsTheEventsAdults() {
        #expect(SchedulerPage.allCases.filter(\.listsAdults) == [.adults])
    }

    @Test func onlyTheAdultHistoryPageListsTheHistory() {
        #expect(SchedulerPage.allCases.filter(\.listsAdultHistory) == [.adultHistory])
    }

    @Test func theAdultsAndTheirHistoryAreNeverTheBoardsPages() {
        // Adults are put on a board from the inspector, and the pages that
        // list adults have none.
        for page in SchedulerPage.allCases where page.listsAdults || page.listsAdultHistory {
            #expect(!page.showsBoard)
        }
    }

    @Test func theYouthPageListsEveryYouthWhateverTheirStatus() {
        for status in BoardStatus.allCases {
            #expect(SchedulerPage.youth.listsYouth(with: status))
        }
        #expect(SchedulerPage.youth.listsYouth(with: nil))
    }

    @Test func resultsListsTheBoardsSeatedOrFinishedAndNotThoseStillWaiting() {
        #expect(SchedulerPage.results.listsYouth(with: .seated))
        #expect(SchedulerPage.results.listsYouth(with: .inProgress))
        #expect(SchedulerPage.results.listsYouth(with: .completed))
        #expect(SchedulerPage.results.listsYouth(with: .postponed))
        #expect(!SchedulerPage.results.listsYouth(with: .registered))
        #expect(!SchedulerPage.results.listsYouth(with: .verified))
        // A status Eagle Boards does not know is not a board.
        #expect(!SchedulerPage.results.listsYouth(with: nil))
    }

    @Test func noOtherPageListsYouthToShowOnTheEventPage() {
        let others: [SchedulerPage] = [.event, .adults, .preRegistered, .adultHistory, .rooms, .approvedProposals]
        for page in others {
            for status in BoardStatus.allCases {
                #expect(!page.listsYouth(with: status))
            }
            #expect(!page.listsYouth(with: nil))
        }
    }

    @Test func theInspectorIsOnScreenOnlyOnTheEventPageAndOnlyIfChosen() {
        #expect(SchedulerPage.event.showsInspector(chosen: true))
        #expect(!SchedulerPage.event.showsInspector(chosen: false))
        for page in SchedulerPage.allCases where page != .event {
            #expect(!page.showsInspector(chosen: true))
            #expect(!page.showsInspector(chosen: false))
        }
    }

    @Test func theOperatorClosingTheInspectorOnTheEventPageIsAChoice() {
        #expect(!SchedulerPage.event.inspectorChoice(reported: false, was: true))
        #expect(SchedulerPage.event.inspectorChoice(reported: true, was: false))
    }

    @Test func theInspectorLeavingWithAPageIsNotAChoice() {
        // SwiftUI reports the inspector closed when the page takes it away.
        for page in SchedulerPage.allCases where !page.showsBoard {
            #expect(page.inspectorChoice(reported: false, was: true))
            #expect(!page.inspectorChoice(reported: false, was: false))
            // Nor does anything reported from a page without it turn it on.
            #expect(!page.inspectorChoice(reported: true, was: false))
        }
    }

    @Test func aChosenInspectorComesBackWithTheEventPage() {
        var chosen = true
        // Event, then Results, which takes the inspector away and hears it
        // closed, then Event again.
        chosen = SchedulerPage.event.inspectorChoice(reported: true, was: chosen)
        chosen = SchedulerPage.results.inspectorChoice(reported: false, was: chosen)
        #expect(SchedulerPage.event.showsInspector(chosen: chosen))
    }

    @Test func anInspectorTheOperatorHidKeepsItselfHiddenAcrossPages() {
        var chosen = true
        chosen = SchedulerPage.event.inspectorChoice(reported: false, was: chosen)
        chosen = SchedulerPage.rooms.inspectorChoice(reported: false, was: chosen)
        #expect(!SchedulerPage.event.showsInspector(chosen: chosen))
    }

    // MARK: - Where Undo and Redo land

    /// Each page and the page that shows a change to a board, a room, and an
    /// adult, written out so the answers do not come from the code they test.
    private static let landings: [(from: SchedulerPage, board: SchedulerPage, rooms: SchedulerPage, adults: SchedulerPage)] = [
        (.event, .event, .event, .adults),
        (.results, .event, .event, .adults),
        (.adults, .event, .event, .adults),
        (.youth, .event, .event, .adults),
        (.preRegistered, .event, .event, .adults),
        (.adultHistory, .event, .event, .adults),
        (.rooms, .event, .rooms, .adults),
        (.approvedProposals, .event, .event, .adults),
    ]

    @Test func theTableCoversEveryPage() {
        #expect(Self.landings.map(\.from) == SchedulerPage.allCases)
    }

    @Test func aBoardChangeLandsOnTheEventPageFromEveryPage() {
        for landing in Self.landings {
            #expect(landing.from.revealing(.board) == landing.board, "from \(landing.from)")
        }
    }

    @Test func aRoomChangeStaysOnAPageThatShowsRoomsAndOtherwiseGoesToTheEventPage() {
        for landing in Self.landings {
            #expect(landing.from.revealing(.rooms) == landing.rooms, "from \(landing.from)")
        }
    }

    @Test func anAdultChangeLandsOnTheAdultsPageFromEveryPage() {
        for landing in Self.landings {
            #expect(landing.from.revealing(.adults) == landing.adults, "from \(landing.from)")
        }
    }

    @Test func everyChangeLandsOnAPageThatShowsIt() {
        for page in SchedulerPage.allCases {
            #expect(page.revealing(.board).showsBoard)
            #expect(page.revealing(.rooms).showsRooms)
            #expect(page.revealing(.adults).listsAdults)
        }
    }

    @Test func aPageThatLandedOnShowsTheChangeAndIsNotMovedAgain() {
        for subject in SchedulerPage.Subject.allCases {
            for page in SchedulerPage.allCases {
                let landing = page.revealing(subject)
                #expect(landing.revealing(subject) == landing)
            }
        }
    }
}
