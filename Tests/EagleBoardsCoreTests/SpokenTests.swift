import EagleBoardsCore
import Foundation
import Testing

// What VoiceOver hears and the screen does not show (SPEC.md D-14), in the
// Windows version's words (c0b18db) with the Mac's command names.

@Suite("A step that worked, said")
struct StepSpeechTests {
    @Test func theBoardSteps() {
        #expect(StepSpeech.seated("Jane Doe", room: "101") == "Jane Doe's board is seated in room 101. Start Review is next.")
        #expect(StepSpeech.reviewStarted("Jane Doe", room: "101") == "Jane Doe's review has started in room 101. Complete is next.")
        #expect(StepSpeech.completed("Jane Doe", result: .notApproved, room: "101")
                == "Jane Doe's board is complete: Not Approved. Room 101 is free.")
        #expect(StepSpeech.reset("Jane Doe", room: "101") == "Jane Doe is waiting again. Room 101 is free.")
        #expect(StepSpeech.reset("Jane Doe", room: "") == "Jane Doe is waiting again.", "a board that held no room")
        #expect(StepSpeech.postponed("Jane Doe") == "Jane Doe's board is postponed.")
    }

    @Test func changeMembersSaysTheWholeChangeAtOnce() {
        let board = ["Ann Able", "Bob Baker", "Cy Cole"]
        #expect(StepSpeech.membersChanged(before: board, after: ["Ann Able", "Dee Dunn", "Cy Cole"],
                                          chairBefore: "Ann Able", chairAfter: "Ann Able")
                == "Dee Dunn replaces Bob Baker on the board.")
        #expect(StepSpeech.membersChanged(before: board, after: ["Ann Able", "Cy Cole"], chairBefore: "Ann Able", chairAfter: "Ann Able")
                == "Bob Baker is off the board.")
        #expect(StepSpeech.membersChanged(before: board, after: board + ["Dee Dunn", "Eve Ellis"],
                                          chairBefore: "Ann Able", chairAfter: "Ann Able")
                == "Dee Dunn and Eve Ellis are on the board.")
        #expect(StepSpeech.membersChanged(before: board, after: ["Dee Dunn", "Eve Ellis", "Fay Fox", "Gus Gray"],
                                          chairBefore: "Ann Able", chairAfter: "Dee Dunn")
                == "Ann Able, Bob Baker, and Cy Cole are off the board. Dee Dunn, Eve Ellis, Fay Fox, and Gus Gray are on the board. "
                    + "Dee Dunn is now the chair.")
        #expect(StepSpeech.membersChanged(before: board, after: board, chairBefore: "Ann Able", chairAfter: "Cy Cole")
                == "Cy Cole is now the chair.")
        #expect(StepSpeech.membersChanged(before: board, after: board, chairBefore: "Ann Able", chairAfter: "Ann Able")
                == "The board's members are unchanged.")
    }

    /// One adult by name; several by how many, as Adult › Mark Gone Home
    /// and Sign In for Today act on every one selected.
    @Test func adultsByNameOrByCount() {
        #expect(StepSpeech.markedGoneHome(["Bob Smith"]) == "Bob Smith is marked gone home.")
        #expect(StepSpeech.markedGoneHome(["Bob Smith", "Ann Lee", "Cy Cole"]) == "3 adults are marked gone home.")
        #expect(StepSpeech.markedBack(["Bob Smith"]) == "Bob Smith is marked back.")
        #expect(StepSpeech.markedBack(["Bob Smith", "Ann Lee"]) == "2 adults are marked back.")
        #expect(StepSpeech.signedIn(["Bob Smith"]) == "Bob Smith is signed in for today.")
        #expect(StepSpeech.signedIn(["Bob Smith", "Ann Lee", "Cy Cole"]) == "3 adults are signed in for today.")
        #expect(StepSpeech.signedIn([]).isEmpty)
        #expect(StepSpeech.linked("Sam Scoutmaster", to: "Jane Doe") == "Sam Scoutmaster is linked to Jane Doe.")
        #expect(StepSpeech.unlinked("Sam Scoutmaster", from: "Jane Doe") == "Sam Scoutmaster is no longer linked to Jane Doe.")
    }

    @Test func roomSteps() {
        #expect(StepSpeech.roomAdded("101") == "Room 101 added.")
        #expect(StepSpeech.roomRemoved("101") == "Room 101 removed.")
        #expect(StepSpeech.roomRenamed("101", to: "102") == "Room 101 is now room 102.")
        #expect(StepSpeech.roomUse("200A", .projectReview) == "Room 200A is now for Proposal Reviews.")
        let us = Locale(identifier: "en_US")
        #expect(StepSpeech.roomsCopied(3, from: "2026-09-22", locale: us) == "3 rooms copied from September 22, 2026.")
        #expect(StepSpeech.roomsCopied(1, from: "2026-09-22", locale: us) == "1 room copied from September 22, 2026.")
    }

    @Test func moveBoardSaysWhichWayItWent() {
        #expect(StepSpeech.boardMoved(from: "101", holding: "Jane Doe", to: "102", holding: "Bill Amend")
                == "The boards in rooms 101 and 102 swapped rooms.")
        #expect(StepSpeech.boardMoved(from: "101", holding: "Jane Doe", to: "102", holding: nil) == "Jane Doe's board moved to room 102.")
        #expect(StepSpeech.boardMoved(from: "101", holding: nil, to: "102", holding: "Bill Amend") == "Bill Amend's board moved to room 101.")
        #expect(StepSpeech.boardMoved(from: "101", holding: nil, to: "102", holding: nil) == "Rooms 101 and 102 are both free.")
    }

    @Test func undoAndRedoNameTheStep() {
        #expect(StepSpeech.undid("Seat Board") == "Undid Seat Board.")
        #expect(StepSpeech.redid("Change Room Use") == "Redid Change Room Use.")
    }
}

@Suite("Sign-ins at the door, said")
struct ArrivalsTests {
    @Test(arguments: [
        ([String](), [String](), ""),
        (["Jane Doe"], [], "Jane Doe signed in."),
        ([], ["Bob Smith"], "Bob Smith signed in."),
        (["Jane Doe", "Bill Amend", "Rob Corddry"], [], "3 youth signed in."),
        ([], ["Bob Smith", "Ann Lee"], "2 adults signed in."),
        (["Jane Doe", "Bill Amend"], ["Bob Smith"], "2 youth and 1 adult signed in."),
    ])
    func oneSentenceHoweverManyCame(youth: [String], adults: [String], sentence: String) {
        #expect(Arrivals.sentence(youth: youth, adults: adults) == sentence)
    }
}

@Suite("Search counts, said")
struct SearchSpeechTests {
    @Test func aTableSaysHowManyItShows() {
        #expect(SearchSpeech.tableCount(shown: 40, total: 40) == "40 records")
        #expect(SearchSpeech.tableCount(shown: 12, total: 40) == "12 of 40 records")
        #expect(SearchSpeech.tableCount(shown: 0, total: 1) == "0 of 1 record")
        #expect(SearchSpeech.tableCount(shown: 1, total: 1) == "1 record")
    }

    @Test func addAdultSaysHowManyTheHistoryHolds() {
        #expect(SearchSpeech.historyFound(total: 0, shown: 0) == "No one in the adult history matches.")
        #expect(SearchSpeech.historyFound(total: 1, shown: 1) == "1 adult found.")
        #expect(SearchSpeech.historyFound(total: 3, shown: 3) == "3 adults found.")
        #expect(SearchSpeech.historyFound(total: 12, shown: 5)
                == "12 adults found, the first 5 shown. Type more of the name to narrow them down.")
    }
}

@Suite("Rows and cards, read aloud")
struct SpokenRowTests {
    private func youth(_ status: BoardStatus, regNum: String = "W9", boardType: String = "Project", room: String = "",
                       result: String = "") -> Scout {
        Scout(fields: [
            "Type": "SCOUT", "ID": "SCOUT:Doe:Jane:1409", "First": "Jane", "Last": "Doe", "RegNum": regNum,
            "UnitName": "Troop1409", "BoardType": boardType, "Status": status.rawValue, "Room": room, "Result": result,
        ])
    }

    /// The youth list reads the name, then where they are in words and the
    /// second line with commas (Windows' QueueStatus and SubLineSpoken).
    @Test func aYouthIsReadAsWhereTheyAre() {
        #expect(youth(.registered).queueValue(minutes: 12, timer: nil) == "Waiting 12 minutes, W9, Troop 1409, Proposal Review")
        #expect(youth(.registered).queueValue(minutes: 1, timer: nil) == "Waiting 1 minute, W9, Troop 1409, Proposal Review")
        #expect(youth(.seated, boardType: "Final", room: "101").queueValue(minutes: 31, timer: .overdue)
                == "Seated, convening for 31 minutes, overdue, W9, Troop 1409, Room 101")
        #expect(youth(.inProgress, room: "200A").queueValue(minutes: 26, timer: .warning)
                == "In review for 26 minutes, running long, W9, Troop 1409, Room 200A")
        #expect(youth(.inProgress, room: "200A").queueValue(minutes: 5, timer: .okay)
                == "In review for 5 minutes, W9, Troop 1409, Room 200A")
        #expect(youth(.completed, regNum: "P1", boardType: "Final", result: "Approved").queueValue(minutes: 3, timer: nil)
                == "Completed, Approved, P1, Troop 1409, Final Board")
        #expect(youth(.postponed).queueValue(minutes: 3, timer: nil) == "Postponed, W9, Troop 1409, Proposal Review")
        #expect(youth(.registered).queueValue(minutes: nil, timer: nil) == "Waiting, W9, Troop 1409, Proposal Review",
                "no stamp to time from")
    }

    @Test func minutesAreSaidInFull() {
        #expect(youth(.registered).timeText(minutes: 1) == "Waiting 1 minute")
        #expect(youth(.seated).timeText(minutes: 12) == "Board convening for 12 minutes")
        #expect(youth(.inProgress).timeText(minutes: 12) == "In review for 12 minutes")
        #expect(youth(.completed).timeText(minutes: 12) == "Finished 12 minutes ago")
        #expect(youth(.registered, regNum: "W3").queueHelp(minutes: 12)
                == "Waiting 12 minutes. Walk-in: no pre-registration matched. The 3rd walk-in to sign in.")
        #expect(youth(.registered, regNum: "W").queueHelp(minutes: nil).isEmpty)
    }

    /// Windows' RoomCard.AccessibleName, with the status the Mac card shows.
    @Test func aRoomCardNamesItsMembersAsMembers() {
        func room(scout: String = "", leaders: String = "") -> Room {
            Room(fields: ["Type": "ROOM", "ID": "ROOM:101", "Room": "101", "BoardType": "Final", "Scout": scout, "Leaders": leaders])
        }
        let jane = youth(.seated, boardType: "Final", room: "101")
        #expect(room().spokenLabel(occupant: nil, adults: [], minutes: nil, timer: nil) == "Room 101, Final Board, free")
        #expect(room(scout: "-").spokenLabel(occupant: nil, adults: [], minutes: nil, timer: nil) == "Room 101, Final Board, free",
                "an old file's dash")
        #expect(room(scout: "Jane Doe", leaders: "Bob Smith,Ann Lee").spokenLabel(occupant: jane, adults: [], minutes: 12, timer: .okay)
                == "Room 101, Final Board, Jane Doe, Seated, 12 minutes, members Bob Smith, Ann Lee")
        #expect(room(scout: "Jane Doe", leaders: "Bob Smith~Ann Lee").spokenLabel(occupant: jane, adults: [], minutes: 31, timer: .overdue)
                == "Room 101, Final Board, Jane Doe, Seated, 31 minutes, overdue, members Bob Smith, Ann Lee")
        #expect(room(scout: "Jane Doe", leaders: "Bob Smith").spokenLabel(occupant: jane, adults: [], minutes: 12, timer: nil)
                == "Room 101, Final Board, Jane Doe, Seated, member Bob Smith", "no timer shown, no minutes said")
    }

    /// An adult beside a board is one element, read in the order the row
    /// shows it (Windows' PickRow.Spoken).
    @Test func anAdultRowIsReadInOne() {
        let bob = Adult(fields: [
            "Type": "ADULT", "ID": "ADULT:Smith:Bob:1409", "First": "Bob", "Last": "Smith", "UnitName": "Troop1409",
            "FinalBoard": "Chair", "WoodBadge": "Y",
        ])
        let jane = youth(.registered, boardType: "Final")
        #expect(bob.spokenRow(youth: jane, place: bob.unitDisplay, role: BoardRole.chair.label)
                == "Bob Smith, Wood Badge, Same unit, Troop 1409, Chair")
        #expect(bob.spokenRow(youth: nil, place: "Gone home", role: "Can Chair") == "Bob Smith, Wood Badge, Gone home, Can Chair")
        #expect(BoardRole.unavailable.label == "No Thanks" && BoardRole.member.label == "Member")
    }

    @Test func middleDotsAreReadAsCommas() {
        #expect("W9 · Troop 1409 · Final Board".spokenList == "W9, Troop 1409, Final Board")
        #expect("Room 101 · Final Board · chaired by Ann Lee. The room is freed.".spokenList
                == "Room 101, Final Board, chaired by Ann Lee. The room is freed.")
        #expect("Bob Smith~Ann Lee, Cy Cole".memberLines == ["Bob Smith", "Ann Lee", "Cy Cole"])
    }
}
