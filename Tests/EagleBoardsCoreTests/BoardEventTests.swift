import EagleBoardsCore
import Foundation
import Testing

/// A whole board event at the district's real shape, carried over from the
/// Java project's scripts/test-board-event.sh:
///
///   14 youth (9 Final, 5 Project)     12 rooms (7 Final, 5 Project)
///   30 adults, of whom only FIVE may chair anything:
///       3 can chair a Final board, 3 a Project review, one of them both.
///
/// So the event is capped at five concurrent boards no matter how many rooms
/// are free -- the constraint the scheduler actually has to survive. The rule
/// tests pin down the rules as pure functions; this pins down what the event
/// does with them: boards convening and starting, adults committed to
/// one room and released when the review finishes, boards postponed and reset,
/// and the rules holding even for requests that skip the Seat Board sheet.
///
/// Add a case here when you change how a board is seated, run or torn down.
@MainActor
@Suite("A board event")
struct BoardEventTests {
    let scratch: ScratchFolder
    let event: BoardEvent

    let adultLastNames = """
        Abernathy Blackwood Castellano Duxbury Ellsworth Fairbanks Grimaldi Hollingsworth
        Ivanovic Jankowski Kaminski Lindqvist Montgomery Nakamura Oyelaran Pemberton
        Quintanilla Rasmussen Stavropoulos Thornbury Uddin Vandermeer Whitfield Xiong
        Yarborough Zeltser Ashworth Bellweather Crowninshield Devereaux
        """.split(whereSeparator: \.isWhitespace).map(String.init)
    let adultFirstNames = """
        Anneliese Bartholomew Clementine Desmond Evangeline Fitzgerald Genevieve Horatio
        Isadora Jebediah Katarina Leopold Marguerite Nathaniel Ophelia Percival
        Quintessa Roderick Seraphina Thaddeus Ulyana Vivienne Wilhelmina Xavier
        Yolanda Zacharias Augustina Benedikt Cordelia Dashiell
        """.split(whereSeparator: \.isWhitespace).map(String.init)
    let youthLastNames = """
        Aldridge Bram Carrington Dunmore Everly Fenwick Gallagher Harrington
        Iverson Jessup Kirkland Lockhart Merriweather Northcott
        """.split(whereSeparator: \.isWhitespace).map(String.init)
    let youthFirstNames = """
        Alexander Beauregard Cormac Dorian Emmett Finnegan Gideon Huckleberry
        Ignatius Jasper Kingston Lachlan Montgomery Nicodemus
        """.split(whereSeparator: \.isWhitespace).map(String.init)

    // The five who may chair. chairOfEither can chair either kind, so
    // committing them to a Final board is what drops the event to two Project chairs.
    var chairOfEither: String { adultID(1, unit: 2001) }
    var finalChair2: String { adultID(2, unit: 2002) }
    var finalChair3: String { adultID(3, unit: 2003) }
    var projectChair1: String { adultID(4, unit: 2004) }
    var projectChair2: String { adultID(5, unit: 2005) }
    /// Plain members 1-15 are adults 6-20.
    func member(_ number: Int) -> String { adultID(number + 5, unit: 2000 + number + 5) }
    /// Final youth 1-9 and project youth 1-5 (youth 10-14).
    func finalYouth(_ number: Int) -> String { youthID(number) }
    func projectYouth(_ number: Int) -> String { youthID(number + 9) }

    init() throws {
        scratch = try ScratchFolder()
        event = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")

        for name in ["101", "102", "103", "104", "105", "106", "107"] {
            try event.addRoom(named: name, boardType: .finalBoard)
        }
        for name in ["200A", "200B", "201A", "201B", "202"] {
            try event.addRoom(named: name, boardType: .projectReview)
        }

        try registerAdult(1, unit: 2001, project: "Chair", final: "Chair")
        try registerAdult(2, unit: 2002, project: "Member", final: "Chair")
        try registerAdult(3, unit: 2003, project: "Member", final: "Chair")
        try registerAdult(4, unit: 2004, project: "Chair", final: "Member")
        try registerAdult(5, unit: 2005, project: "Chair", final: "Member")
        for number in 6...25 {
            try registerAdult(number, unit: 2000 + number, project: "Member", final: "Member")
        }
        // Two who cannot do a project review, and three who share a unit with
        // youth 1-3 so the same-unit rule has something real to catch.
        try registerAdult(26, unit: 2026, project: "Unavailable", final: "Member")
        try registerAdult(27, unit: 2027, project: "Unavailable", final: "Member")
        try registerAdult(28, unit: 1001, project: "Member", final: "Unavailable")
        try registerAdult(29, unit: 1002, project: "Member", final: "Unavailable")
        try registerAdult(30, unit: 1003, project: "Member", final: "Unavailable")

        for number in 1...14 {
            try event.registerYouth([
                "Last": youthLastNames[number - 1], "First": youthFirstNames[number - 1],
                "Email": "s\(number)@example.org", "UnitType": "Troop", "Unit": "\(1000 + number)",
                "BoardType": number <= 9 ? "Final" : "Project",
            ])
        }
    }

    private func adultID(_ number: Int, unit: Int) -> String {
        "ADULT:\(adultLastNames[number - 1]):\(adultFirstNames[number - 1]):\(unit)"
    }

    private func youthID(_ number: Int) -> String {
        "SCOUT:\(youthLastNames[number - 1]):\(youthFirstNames[number - 1]):\(1000 + number)"
    }

    private func registerAdult(_ number: Int, unit: Int, project: String, final: String) throws {
        try event.registerAdult([
            "Last": adultLastNames[number - 1], "First": adultFirstNames[number - 1],
            "Email": "a\(number)@example.org", "UnitType": "Troop", "Unit": "\(unit)",
            "ProjectReview": project, "FinalBoard": final,
        ])
    }

    // MARK: - Helpers that read the event back

    /// Seat a board in the room by that name. A renamed room keeps its ID,
    /// so the ID is looked up; a name no room has stands for an unknown ID.
    private func seat(_ roomName: String, _ scoutID: String, chair: String, _ members: String...) throws {
        let roomID = event.room(named: roomName)?.id ?? "ROOM:\(roomName)"
        try event.seatBoard(roomID: roomID, scoutID: scoutID, chairID: chair, memberIDs: [chair] + members)
    }

    private func refused(_ what: Comment, _ action: () throws -> Void) {
        #expect(throws: EventError.self, what, performing: action)
    }

    /// The words a refusal shows, or nil when nothing was refused.
    private func refusal(_ action: () throws -> Void) -> String? {
        do {
            try action()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func count(_ status: BoardStatus) -> Int { event.scouts.filter { $0.status == status }.count }
    private var busyAdults: Int { event.adults.filter(\.isOnBoard).count }
    private var emptyRooms: Int { event.rooms.filter(\.isFree).count }
    private func status(_ scoutID: String) -> BoardStatus? { event.scout(id: scoutID)?.status }
    private func roomOf(_ scoutID: String) -> String? { event.scout(id: scoutID)?.room }
    private func adultRoom(_ adultID: String) -> String? { event.adult(id: adultID)?.room }

    private func runBoard(_ scoutID: String) throws {
        try event.startReview(scoutID: scoutID)
        try event.completeBoard(scoutID: scoutID, result: .approved, notes: "")
    }

    // MARK: - The event

    @Test func theEventAsSeeded() {
        #expect(event.rooms.count == 12)
        #expect(event.adults.count == 30)
        #expect(event.scouts.count == 14)
        #expect(event.adults.filter { $0.canChair(.finalBoard) || $0.canChair(.projectReview) }.count == 5)
    }

    /// Three adults in finalYouth(1)'s unit, Troop 1001, who may sit on a
    /// Final board: a chair and two members.
    private func ownUnitAdults() throws -> [String] {
        try [("Kettleborough", "Philippa", "Chair"), ("Lanchester", "Rosamund", "Member"), ("Marchbanks", "Tiberius", "Member")]
            .map { last, first, role in
                try event.registerAdult([
                    "Last": last, "First": first, "Email": "\(first.lowercased())@example.org", "UnitType": "Troop", "Unit": "1001",
                    "ProjectReview": "Member", "FinalBoard": role,
                ]).id
            }
    }

    @Test func compositionRulesHoldWithoutTheSeatBoardSheet() throws {
        refused("a Final board of 2 (GTA 8.0.0.3 floor)") { try seat("101", finalYouth(1), chair: chairOfEither, member(1)) }
        refused("a Final board of 7 (GTA 8.0.0.3 ceiling)") { try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2), member(3), member(4), member(5), member(6)) }
        refused("a project review of 1") { try seat("200A", projectYouth(1), chair: projectChair1) }
        refused("a project review of 7") { try seat("200A", projectYouth(1), chair: projectChair1, member(1), member(2), member(3), member(4), member(5), member(6)) }

        refused("a plain Member may not chair a Final board") { try seat("101", finalYouth(1), chair: member(1), member(2), member(3)) }
        refused("a Project chair may not chair a Final board") { try seat("101", finalYouth(1), chair: projectChair1, member(1), member(2)) }
        refused("a plain Member may not chair a project review") { try seat("200A", projectYouth(1), chair: member(1), member(2)) }
        refused("the chair must be sitting on the board") {
            try event.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: finalChair2, memberIDs: [member(1), member(2), member(3)])
        }
        refused("an unknown chair") {
            try event.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: "NOBODY", memberIDs: [member(1), member(2), member(3)])
        }
        refused("a board with no members") {
            try event.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [])
        }
        refused("the same member listed twice does not make a board of three") {
            try event.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(1), member(1)])
        }

        // SPEC.md D-4: the council's same-unit rule can be overridden, but
        // not past the national floor of one member from outside the unit.
        let own = try ownUnitAdults()
        do {
            try seat("101", finalYouth(1), chair: own[0], own[1], own[2])
            Issue.record("a board all from the youth's own unit is refused (GTA 8.0.3.0)")
        } catch let refusal as EventError {
            let youth = try #require(event.scout(id: finalYouth(1)))
            let review = SeatingReview(scout: youth, members: own.compactMap(event.adult(id:)), room: event.room(named: "101"))
            #expect(review.blockingProblems.contains(refusal.message), "in the words the Seat Board sheet uses")
        }

        #expect(count(.seated) == 0, "none of that seated anyone")
        #expect(busyAdults == 0)
    }

    /// Windows' SeatingRefusalsSayWhatToDoInTheWindowsWords: the backstop's
    /// refusals use the screen's words (the board type as shown, "gone
    /// home", a count with no "(s)") and say what to do.
    @Test func seatingRefusalsSayWhatToDoInTheScreensWords() throws {
        func seating(_ chair: String, _ members: [String], in room: String = "ROOM:101", youth: String? = nil) -> String? {
            refusal { try event.seatBoard(roomID: room, scoutID: youth ?? finalYouth(1), chairID: chair, memberIDs: members) }
        }
        #expect(seating(chairOfEither, []) == "The board has no members yet. Add at least 3 for a Final Board.")
        #expect(seating(chairOfEither, [chairOfEither])
            == "Only 1 member is on the board, and a Final Board needs at least 3. Add 2 more.")
        #expect(seating(chairOfEither, [chairOfEither, member(1)])
            == "Only 2 members are on the board, and a Final Board needs at least 3. Add 1 more.")
        #expect(seating(chairOfEither, [chairOfEither] + (1...6).map(member))
            == "7 members are on the board, and a Final Board can have at most 6 (Guide to Advancement 8.0.0.3). Remove 1.")
        #expect(seating(projectChair1, [projectChair1], in: "ROOM:200A", youth: projectYouth(1))
            == "Only 1 member is on the board, and a Proposal Review needs at least 2. Add 1 more.")

        #expect(seating("", [chairOfEither, member(1), member(2)])
            == "No one is chosen to chair the board. Choose which qualified member chairs it.")
        #expect(seating(finalChair2, [member(1), member(2), member(3)])
            == "Bartholomew Blackwood would chair the board but isn't one of its members. Add them to the board, or choose another chair.")
        #expect(seating(member(1), [member(1), member(2), member(3)])
            == "Fitzgerald Fairbanks isn't a chair for Final Boards. Choose a qualified chair, or make them a chair on the Adults page.")
        #expect(seating(projectChair1, [projectChair1, member(1), member(2)])
            == "Desmond Duxbury isn't a chair for Final Boards. Choose a qualified chair, or make them a chair on the Adults page.")

        try event.setAvailable(false, adultID: member(11))
        #expect(seating(chairOfEither, [chairOfEither, member(1), member(11)])
            == "Percival Pemberton has gone home. Bring them back with Adult › Mark Back, or choose someone else.")
        let noThanks = adultID(29, unit: 1002)  // Unavailable for Final Boards
        #expect(seating(chairOfEither, [chairOfEither, member(1), noThanks])
            == "Cordelia Crowninshield said no thanks to Final Boards. Choose someone else.")
        #expect(seating(chairOfEither, [chairOfEither, member(1), "ADULT:Nobody:Here:0"]) == "There is no adult 'ADULT:Nobody:Here:0'.")

        let own = try ownUnitAdults()
        #expect(seating(own[0], own) == "Every selected member is in Troop 1001, Alexander Aldridge's own unit. "
            + "A board needs at least one member from outside the unit (Guide to Advancement 8.0.3.0). Add someone from another unit.")

        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))
        #expect(seating(chairOfEither, [chairOfEither, member(1), member(3)])
            == "Horatio Hollingsworth is on the board in room 102. Choose someone else.")
        #expect(seating(chairOfEither, [chairOfEither, member(1), member(2)], in: "ROOM:102")
            == "Room 102 already has Beauregard Bram's board. Choose a free room.")
        #expect(count(.seated) == 1, "none of that seated anyone")
    }

    /// The same refusals for a board already sitting say what would be left
    /// and end "before saving". Windows' TheChairLeavingASittingBoardIsTold...
    /// has no counterpart: Change Members hands the chair to the first
    /// qualified member when the chair is taken off, so the core only ever
    /// sees a chair who is not among the members, refused as at seating.
    @Test func changeMembersRefusalsSayWhatWouldBeLeft() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        func changing(_ chair: String, _ members: [String]) -> String? {
            refusal { try event.changeMembers(scoutID: finalYouth(1), chairID: chair, memberIDs: members) }
        }
        #expect(changing(chairOfEither, [])
            == "No members would be left, and a Final Board needs at least 3. Add 3 before saving.")
        #expect(changing(chairOfEither, [chairOfEither, member(1)])
            == "Only 2 members would be left, and a Final Board needs at least 3. Add 1 more before saving.")
        #expect(changing(chairOfEither, [chairOfEither] + (1...6).map(member))
            == "That would make 7 members, and a Final Board can have at most 6 (Guide to Advancement 8.0.0.3). Remove 1 before saving.")
        #expect(changing(chairOfEither, [finalChair2, member(1), member(2)])
            == "Anneliese Abernathy would chair the board but isn't one of its members. Add them to the board, or choose another chair.")
        #expect(adultRoom(member(2)) == "101", "the refusals changed nothing")
    }

    /// SPEC.md D-1: a refusal shows a name with its comma, as the screen
    /// does, though the files keep it as "~" and the record reads it back so.
    @Test func aRefusalShowsANameWithItsComma() throws {
        try event.registerAdult([
            "Last": "Whitmore, Jr.", "First": "Lysander", "Email": "a31@example.org",
            "UnitType": "Troop", "Unit": "2031", "ProjectReview": "Member", "FinalBoard": "Member",
        ])
        let junior = "ADULT:Whitmore~ Jr.:Lysander:2031"
        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        try reopened.setAvailable(false, adultID: junior)
        let refused = refusal {
            try reopened.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: chairOfEither,
                                   memberIDs: [chairOfEither, member(1), junior])
        }
        #expect(refused == "Lysander Whitmore, Jr. has gone home. Bring them back with Adult › Mark Back, or choose someone else.")
        #expect(refusal { try reopened.setAvailable(false, adultID: junior) } == "Lysander Whitmore, Jr. is already marked gone home.")

        let youth = try #require(reopened.scout(id: finalYouth(1)))
        let members = [chairOfEither, member(1), junior].compactMap(reopened.adult(id:))
        #expect(SeatingReview(scout: youth, members: members, room: reopened.room(named: "101")).blockingProblems
            == ["Lysander Whitmore, Jr. has gone home. Remove them, or bring them back with Adult › Mark Back."])
    }

    /// A table never deletes someone a board holds (SPEC.md P-6, amended
    /// 2026-10-24; the event test's section 29): a youth whose board is
    /// seated or in review, or a member sitting on it, until it is over.
    @Test func aTableNeverDeletesSomeoneABoardHolds() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        #expect(refusal { try event.deleteYouth(id: finalYouth(1)) }?.hasSuffix("Reset or complete that board first.") == true,
                "a seated youth is not deleted")
        #expect(refusal { try event.deleteAdult(id: member(1)) } != nil, "nor a member of their board")
        try event.startReview(scoutID: finalYouth(1))
        #expect(refusal { try event.deleteYouth(id: finalYouth(1)) } != nil, "nor a youth in review")
        #expect(refusal { try event.deleteAdult(id: chairOfEither) } != nil, "nor its chair")
        #expect(event.scout(id: finalYouth(1))?.status == .inProgress, "the board keeps its youth")
        try event.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "")
        try event.deleteYouth(id: finalYouth(1))
        #expect(event.scout(id: finalYouth(1)) == nil, "a youth whose board is over can be deleted")
    }

    /// Marking an adult gone home or back, deleting one, and Undo say the
    /// way out (Windows' DisableAdult and Undo). Undo and Redo share
    /// restoreBoard, so its ending fits either.
    @Test func goneHomeDeleteAndUndoRefusalsNameTheWayOut() throws {
        #expect(refusal { try event.setAvailable(true, adultID: member(1)) } == "Fitzgerald Fairbanks isn't marked gone home.")
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        let seated = try #require(event.scout(id: finalYouth(1)))
        let onTheBoard = "Fitzgerald Fairbanks is on the board in room 101. "
            + "Take them off it with Board › Change Members… first, or reset or complete that board."
        #expect(refusal { try event.setAvailable(false, adultID: member(1)) } == onTheBoard)
        #expect(refusal { try event.deleteAdult(id: member(1)) } == onTheBoard)

        try event.resetBoard(scoutID: finalYouth(1))
        try seat("101", finalYouth(2), chair: finalChair2, member(3), member(4))
        #expect(refusal { try event.restoreBoard(seated) }
            == "Room 101 has been given to Beauregard Bram since. Change the board by hand instead.")
        try event.resetBoard(scoutID: finalYouth(2))
        try seat("102", finalYouth(3), chair: finalChair3, member(1), member(5))
        #expect(refusal { try event.restoreBoard(seated) }
            == "Fitzgerald Fairbanks is on the board in room 102 now. Change the board by hand instead.")
        try event.resetBoard(scoutID: finalYouth(3))
        try event.setAvailable(false, adultID: member(2))
        #expect(refusal { try event.restoreBoard(seated) } == "Genevieve Grimaldi has gone home since. Change the board by hand instead.")
        try event.setAvailable(true, adultID: member(2))
        try event.removeRoom(id: "ROOM:101")
        #expect(refusal { try event.restoreBoard(seated) }
            == "Room 101 is no longer on today's list. Change the board by hand instead.")
    }

    @Test func fiveChairsCapTheEventAtFiveConcurrentBoards() throws {
        try seatFiveBoards()
        #expect(count(.seated) == 5)
        #expect(busyAdults == 13)
        #expect(emptyRooms == 7, "seven rooms sit empty for want of a chair")
        #expect(count(.inProgress) == 0, "seating convenes only; the youth is still outside (GTA 8.0.3.0 #8)")

        refused("a seated chair cannot take a second board") { try seat("104", finalYouth(4), chair: chairOfEither, member(9), member(10)) }
        refused("a seated member cannot take a second board") { try seat("104", finalYouth(4), chair: chairOfEither, member(1), member(9)) }
        #expect(status(finalYouth(4)) == .registered)
        #expect(adultRoom(chairOfEither) == "101")
    }

    @Test func anAdultWhoLeavesIsOutUntilReEnabled() throws {
        try seatFiveBoards()
        try event.setAvailable(false, adultID: member(11))
        #expect(adultRoom(member(11)) == disabledForTodayMarker)
        refused("a disabled adult cannot be seated") { try seat("104", finalYouth(4), chair: chairOfEither, member(11), member(12)) }
        refused("an adult on a board cannot be disabled") { try event.setAvailable(false, adultID: member(1)) }

        try event.setAvailable(true, adultID: member(11))
        #expect(adultRoom(member(11)) == "")
    }

    @Test func conveneThenReviewThenComplete() throws {
        try seatFiveBoards()
        refused("a result cannot be recorded while the board is still convening") {
            try event.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "")
        }
        #expect(status(finalYouth(1)) == .seated)

        try event.startReview(scoutID: finalYouth(1))
        #expect(status(finalYouth(1)) == .inProgress)
        refused("a review cannot be started twice") { try event.startReview(scoutID: finalYouth(1)) }

        try event.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "Well prepared, thorough workbook")
        #expect(status(finalYouth(1)) == .completed)
        #expect(event.scout(id: finalYouth(1))?.result == "Approved")
    }

    @Test func completingAReviewReleasesItsAdults() throws {
        try seatFiveBoards()
        try runBoard(finalYouth(1))
        #expect(adultRoom(chairOfEither) == "")
        #expect(adultRoom(member(1)) == "")
        #expect(adultRoom(member(2)) == "")
        #expect(busyAdults == 10)
        #expect(event.room(named: "101")?.isFree == true)

        try seat("104", finalYouth(4), chair: chairOfEither, member(1), member(2))
        #expect(roomOf(finalYouth(4)) == "104")
        #expect(adultRoom(chairOfEither) == "104")
    }

    /// Windows' `ChangeBoardMembers`, ported: the operator can correct who
    /// sits on a board already Seated or InProgress without resetting it,
    /// under the same composition rules `seatBoard` enforces, and Undo
    /// generalizes to it through `restoreBoard` with no changes of its own.
    @Test func changeMembersCorrectsWhoSitsWithoutResettingTheRoom() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        let seated = try #require(event.scout(id: finalYouth(1)))

        refused("only a seated or in-review board can have its members changed") {
            try event.changeMembers(scoutID: finalYouth(2), chairID: finalChair2, memberIDs: [finalChair2, member(3)])
        }

        try event.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(1), member(3)])
        let changed = try #require(event.scout(id: finalYouth(1)))
        #expect(changed.status == .seated, "still seated, not reseated")
        #expect(changed.lastUpdateTime == seated.lastUpdateTime, "the room timer keeps running")
        #expect(changed.boardMemberIDs.split(separator: ",").count == 3)
        #expect(adultRoom(member(2)) == "", "dropped off the board, freed")
        #expect(adultRoom(member(3)) == "101", "added to the board")
        #expect(event.room(named: "101")?.leaderNames == changed.boardMembers)

        try seat("102", finalYouth(2), chair: finalChair2, member(4), member(9))
        refused("a member already on another board cannot be added") {
            try event.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(4)])
        }

        try event.startReview(scoutID: finalYouth(1))
        let inReview = try #require(event.scout(id: finalYouth(1)))
        try event.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(1), member(2)])
        #expect(status(finalYouth(1)) == .inProgress, "changing members mid-review does not end it")
        #expect(event.scout(id: finalYouth(1))?.lastUpdateTime == inReview.lastUpdateTime, "the review timer keeps running too")

        refused("the chair must stay one of the members") {
            try event.changeMembers(scoutID: finalYouth(1), chairID: member(5), memberIDs: [chairOfEither, member(1), member(2)])
        }
        refused("a board of one is below the Final minimum") {
            try event.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither])
        }

        try event.restoreBoard(inReview)
        #expect(adultRoom(member(3)) == "101", "back on the board after undo, as it was mid-review")
        #expect(adultRoom(member(2)) == "", "not on the board being restored to, so freed by the undo")
        #expect(adultRoom(member(1)) == "101")
        #expect(event.scout(id: finalYouth(1))?.boardMemberIDs.split(separator: ",").count == 3)
    }

    /// Java event test section 21, the cases the test above leaves out: the
    /// chair leaving and another chair taking over, a plain member refused
    /// the chair, and Complete releasing whoever sits on the board by then.
    @Test func changeMembersHandsTheChairOnAndCompleteReleasesTheNewBoard() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))

        try event.changeMembers(scoutID: finalYouth(1), chairID: finalChair3, memberIDs: [finalChair3, member(1), member(3)])
        #expect(adultRoom(chairOfEither) == "", "the chair who left is free")
        #expect(adultRoom(member(2)) == "", "the member not kept is free")
        #expect(adultRoom(finalChair3) == "101" && adultRoom(member(3)) == "101", "the new chair and member are in the room")
        #expect(event.scout(id: finalYouth(1))?.boardChairID == finalChair3, "the new chair is recorded")

        refused("a plain member may not take the chair") {
            try event.changeMembers(scoutID: finalYouth(1), chairID: member(1), memberIDs: [finalChair3, member(1), member(3)])
        }
        #expect(event.scout(id: finalYouth(1))?.boardChairID == finalChair3, "the refusal changed nothing")

        try runBoard(finalYouth(1))
        #expect(adultRoom(finalChair3) == "" && adultRoom(member(1)) == "" && adultRoom(member(3)) == "",
                "completing releases the board as changed")
        #expect(busyAdults == 0)
    }

    /// SPEC.md D-4, for a board already sitting: changing its members may
    /// not take off its last member from outside the youth's unit.
    @Test func changeMembersKeepsAMemberFromOutsideTheYouthsUnit() throws {
        let own = try ownUnitAdults()
        try seat("101", finalYouth(1), chair: own[0], own[1], member(1))  // overridden down to the national floor

        refused("a board all from the youth's own unit (GTA 8.0.3.0)") {
            try event.changeMembers(scoutID: finalYouth(1), chairID: own[0], memberIDs: own)
        }
        #expect(adultRoom(member(1)) == "101" && adultRoom(own[2]) == "", "the refusal changed nothing")

        try event.changeMembers(scoutID: finalYouth(1), chairID: own[0], memberIDs: [own[0], own[2], member(2)])
        #expect(adultRoom(member(1)) == "" && adultRoom(member(2)) == "101", "one outside member for another is fine")
    }

    /// In memory a board's member IDs are joined with ","; read back from the
    /// files they are joined with "~" (SPEC.md D-1), and the ID of an adult
    /// whose name has a comma holds "~" itself. After a restart, Change
    /// Members starts from every member, frees whoever it takes off, and
    /// Undo puts the board back.
    @Test func changeMembersAfterTheEventIsReopened() throws {
        try event.registerAdult([
            "Last": "Whitmore, Jr.", "First": "Lysander", "Email": "a31@example.org",
            "UnitType": "Troop", "Unit": "2031", "ProjectReview": "Member", "FinalBoard": "Member",
        ])
        let junior = "ADULT:Whitmore~ Jr.:Lysander:2031"
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), junior)

        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        let before = try #require(reopened.scout(id: finalYouth(1)))
        #expect(!before.boardMemberIDs.contains(","), "the file joined the list with ~")
        let listed = before.boardMembers(among: reopened.adults)
        #expect(listed.members.map(\.id) == [chairOfEither, member(1), junior],
                "Change Members starts from every member, in the board's order")
        #expect(listed.unknown.isEmpty)

        try reopened.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(1), member(2)])
        #expect(reopened.adult(id: junior)?.room == "", "the member taken off is free again")
        #expect(reopened.adult(id: member(2))?.room == "101")

        try reopened.restoreBoard(before)
        #expect(reopened.adult(id: junior)?.room == "101", "Undo puts them back")
        #expect(reopened.adult(id: member(2))?.room == "", "and frees the one who took their place")

        var gone = before
        gone.boardMemberIDs = before.boardMemberIDs + "~ADULT:Nobody:Here:0"
        #expect(gone.boardMembers(among: reopened.adults).unknown == "ADULT:Nobody:Here:0", "and names who it cannot find")
    }

    @Test func postponeAndReset() throws {
        try seatFiveBoards()
        try event.postponeBoard(scoutID: finalYouth(9))
        #expect(status(finalYouth(9)) == .postponed)

        refused("a youth whose board has convened cannot be postponed") { try event.postponeBoard(scoutID: finalYouth(2)) }
        #expect(status(finalYouth(2)) == .seated)

        let busyBefore = busyAdults
        try event.resetBoard(scoutID: finalYouth(2))
        #expect(status(finalYouth(2)) == .registered)
        #expect(roomOf(finalYouth(2)) == "")
        #expect(adultRoom(finalChair2) == "")
        #expect(busyAdults == busyBefore - 3, "the chair and both members are released")

        try event.startReview(scoutID: projectYouth(1))
        try event.resetBoard(scoutID: projectYouth(1))
        #expect(status(projectYouth(1)) == .registered)
        #expect(adultRoom(projectChair1) == "")

        refused("a waiting youth has nothing to reset") { try event.resetBoard(scoutID: finalYouth(2)) }
    }

    @Test func theWholeEventFiveChairsAtATime() throws {
        try seatFiveBoards()
        try runBoard(finalYouth(1))
        try seat("104", finalYouth(4), chair: chairOfEither, member(1), member(2))
        try event.postponeBoard(scoutID: finalYouth(9))
        try event.resetBoard(scoutID: finalYouth(2))
        try event.startReview(scoutID: projectYouth(1))
        try event.resetBoard(scoutID: projectYouth(1))

        // Explicit rather than greedy: assert the outcome expected, not
        // whatever the scheduler managed on the day.
        try runBoard(finalYouth(3))
        try runBoard(projectYouth(2))
        try runBoard(finalYouth(4))
        try seat("101", finalYouth(2), chair: chairOfEither, member(1), member(2)); try runBoard(finalYouth(2))
        try seat("102", finalYouth(5), chair: finalChair2, member(3), member(4)); try runBoard(finalYouth(5))
        try seat("103", finalYouth(6), chair: finalChair3, member(5), member(6)); try runBoard(finalYouth(6))
        try seat("104", finalYouth(7), chair: chairOfEither, member(1), member(2)); try runBoard(finalYouth(7))
        try seat("105", finalYouth(8), chair: finalChair2, member(3), member(4)); try runBoard(finalYouth(8))
        try seat("200A", projectYouth(1), chair: projectChair1, member(7)); try runBoard(projectYouth(1))
        try seat("200B", projectYouth(3), chair: projectChair2, member(8)); try runBoard(projectYouth(3))
        try seat("201A", projectYouth(4), chair: projectChair1, member(7)); try runBoard(projectYouth(4))
        try seat("201B", projectYouth(5), chair: projectChair2, member(8)); try runBoard(projectYouth(5))

        #expect(count(.completed) == 13)
        #expect(count(.postponed) == 1)
        #expect(count(.registered) == 0)
        #expect(count(.seated) == 0)
        #expect(count(.inProgress) == 0)
        #expect(busyAdults == 0)
        #expect(emptyRooms == 12)

        // The record is what the district keeps, so a wrong chair on it is the
        // failure that outlives the event.
        for youth in event.scouts where youth.status == .completed {
            let chair = event.adult(id: youth.boardChairID)
            #expect(chair != nil && youth.boardType.map { chair!.canChair($0) } == true, "\(youth.fullName) had a qualified chair")
        }

        // And it is all on disk: a fresh open of the folder sees the same event.
        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        #expect(reopened.scouts.filter { $0.status == .completed }.count == 13)
        #expect(reopened.adults.filter(\.isOnBoard).isEmpty)
        #expect(reopened.rooms.allSatisfy { $0.isFree })
    }

    // MARK: - What goes wrong at the event
    //
    // Carried over from sections 9-18 of the Java project's
    // test-board-event.sh. Where a Java case cannot arise here, the test
    // that stands in for it says why.

    @discardableResult
    private func lateYouth(_ last: String, _ first: String, unit: Int, _ boardType: String = "Final") throws -> String {
        try event.registerYouth([
            "Last": last, "First": first, "Email": "x\(unit)@example.org",
            "UnitType": "Troop", "Unit": "\(unit)", "BoardType": boardType,
        ])
        return "SCOUT:\(last):\(first):\(unit)"
    }

    private func result(_ scoutID: String) -> String? { event.scout(id: scoutID)?.result }

    /// What the Results and Youth pages do: change a youth's fields and save them.
    private func editYouth(_ scoutID: String, _ change: (inout Scout) -> Void) throws {
        var record = try #require(event.scout(id: scoutID))
        change(&record)
        try event.updateYouth(record)
    }

    // Java section 9. Unknown ids and occupied rooms. (Missing parameters and
    // duplicated ids are the Java HTTP API's problem: here members are an
    // array, de-duplicated before they are counted -- see
    // compositionRulesHoldWithoutTheSeatBoardSheet.)
    @Test func requestsTheSeatBoardSheetWouldNeverMake() throws {
        refused("an unknown room") { try seat("999", finalYouth(1), chair: chairOfEither, member(1), member(2)) }
        refused("an unknown youth") { try seat("101", "SCOUT:Nobody:Here:0", chair: chairOfEither, member(1), member(2)) }
        refused("an unknown member") { try seat("101", finalYouth(1), chair: chairOfEither, member(1), "ADULT:Nobody:Here:0") }
        refused("an unknown youth cannot be started") { try event.startReview(scoutID: "SCOUT:Nobody:Here:0") }
        refused("an unknown youth cannot be completed") {
            try event.completeBoard(scoutID: "SCOUT:Nobody:Here:0", result: .approved, notes: "")
        }
        #expect(busyAdults == 0)

        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        refused("nobody else can be seated in an occupied room") { try seat("101", finalYouth(2), chair: finalChair2, member(3), member(4)) }
        refused("the same youth cannot be seated twice") { try seat("102", finalYouth(1), chair: finalChair2, member(3), member(4)) }
        #expect(status(finalYouth(2)) == .registered)
    }

    // Java section 10. Each step only from the status before it. (A made-up
    // result cannot reach completeBoard here: BoardResult is an enum.)
    @Test func eachStepOnlyFromTheStatusBeforeIt() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        try runBoard(finalYouth(1))
        try event.postponeBoard(scoutID: finalYouth(9))

        refused("a Completed youth cannot be seated again") { try seat("102", finalYouth(1), chair: finalChair2, member(3), member(4)) }
        refused("a Postponed youth cannot be seated") { try seat("102", finalYouth(9), chair: finalChair2, member(3), member(4)) }
        refused("a waiting youth cannot be started") { try event.startReview(scoutID: finalYouth(2)) }
        refused("a Completed youth cannot be started") { try event.startReview(scoutID: finalYouth(1)) }
        refused("a waiting youth cannot be completed") { try event.completeBoard(scoutID: finalYouth(2), result: .approved, notes: "") }
        refused("a Completed youth cannot be completed again") {
            try event.completeBoard(scoutID: finalYouth(1), result: .notApproved, notes: "")
        }
        refused("a Completed youth cannot be reset") { try event.resetBoard(scoutID: finalYouth(1)) }
        refused("a Postponed youth cannot be reset") { try event.resetBoard(scoutID: finalYouth(9)) }
        refused("a Completed youth cannot be postponed") { try event.postponeBoard(scoutID: finalYouth(1)) }
        #expect(result(finalYouth(1)) == "Approved", "the result survived all of that")

        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))
        try event.startReview(scoutID: finalYouth(2))
        do {
            try event.postponeBoard(scoutID: finalYouth(2))
            Issue.record("a review under way cannot be postponed")
        } catch let refusal as EventError {
            #expect(refusal.message.hasSuffix("is 'In review'."), "the alert says the badge's word, not the stored InProgress")
        }
        try event.completeBoard(scoutID: finalYouth(2), result: .adjourned, notes: "")
        #expect(result(finalYouth(2)) == "Adjourned")
        try seat("200A", projectYouth(1), chair: projectChair1, member(7))
        try event.startReview(scoutID: projectYouth(1))
        try event.completeBoard(scoutID: projectYouth(1), result: .notApproved, notes: "")
        #expect(result(projectYouth(1)) == "NotApproved")
        #expect(busyAdults == 0)
    }

    // Java section 11.
    @Test func signingInAgainMidBoardChangesNothing() throws {
        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))
        try event.startReview(scoutID: finalYouth(2))
        try registerAdult(8, unit: 2008, project: "Member", final: "Member")  // member(3)
        try registerAdult(2, unit: 2002, project: "Member", final: "Chair")   // finalChair2
        #expect(adultRoom(member(3)) == "102", "a member who signs in again stays in their room")
        #expect(adultRoom(finalChair2) == "102", "so does the chair")
        #expect(event.adult(id: finalChair2)?.canChair(.finalBoard) == true)

        try event.registerYouth([
            "Last": "Bram", "First": "Beauregard", "Email": "again@example.org",
            "UnitType": "Troop", "Unit": "1002", "BoardType": "Final",
        ])
        #expect(status(finalYouth(2)) == .inProgress, "a youth who signs in again is still under review")
        #expect(roomOf(finalYouth(2)) == "102")
        #expect(event.scouts.filter { $0.id == finalYouth(2) }.count == 1, "and is still one youth, not two")
        try event.completeBoard(scoutID: finalYouth(2), result: .approved, notes: "")
        #expect(adultRoom(member(3)) == "")
    }

    // Java section 12.
    @Test func aBoardMovesToAnotherRoom() throws {
        try seat("103", finalYouth(4), chair: finalChair3, member(5), member(6))
        try event.swapRooms("ROOM:103", "ROOM:106")
        #expect(roomOf(finalYouth(4)) == "106")
        #expect([finalChair3, member(5), member(6)].map(adultRoom) == ["106", "106", "106"])
        #expect(event.room(named: "103")?.isFree == true)

        try seat("103", finalYouth(5), chair: chairOfEither, member(1), member(2))
        try event.swapRooms("ROOM:103", "ROOM:106")
        #expect(roomOf(finalYouth(4)) == "103" && roomOf(finalYouth(5)) == "106", "each youth took the other's room")
        #expect(adultRoom(finalChair3) == "103" && adultRoom(chairOfEither) == "106", "each chair went with their own board")
        refused("swapping with a room that does not exist") { try event.swapRooms("ROOM:103", "ROOM:nope") }
        refused("swapping a room with itself") { try event.swapRooms("ROOM:103", "ROOM:103") }

        try runBoard(finalYouth(4))
        #expect(adultRoom(finalChair3) == "" && adultRoom(chairOfEither) == "106", "releasing only its own adults")
        try runBoard(finalYouth(5))
        #expect(busyAdults == 0)
    }

    // Java section 13. The Java Admin page can rename or delete a room under
    // a board, so its server must cope. Here removal is refused while a board
    // is in the room, and a rename carries the board with it (below).
    @Test func aRoomInUseCannotBeRemoved() throws {
        try seat("104", finalYouth(6), chair: chairOfEither, member(1), member(2))
        refused("a room with a board in it cannot be removed") { try event.removeRoom(id: "ROOM:104") }
        try runBoard(finalYouth(6))
        try event.removeRoom(id: "ROOM:104")
        #expect(event.room(named: "104") == nil)
    }

    // Java section 23: a room renamed from its card, empty or with a board
    // in it, keeps its ID and takes the new name, and the names a room
    // cannot take. The tests after them are Windows' for the same rule.
    @Test func anEmptyRoomIsRenamed() throws {
        try event.renameRoom(id: "ROOM:104", to: "  104 Annex ")
        #expect(event.room(id: "ROOM:104")?.name == "104 Annex", "the room keeps its ID and takes the new name, trimmed")
        #expect(event.room(named: "104") == nil)
        #expect(event.room(id: "ROOM:104")?.boardType == .finalBoard, "and keeps what it is used for")
        try seat("104 Annex", finalYouth(1), chair: chairOfEither, member(1), member(2))
        #expect(adultRoom(chairOfEither) == "104 Annex")
        #expect(try event.addRoom(named: "104", boardType: .finalBoard) == "ROOM:104-2",
                "the old name is free again, under the next free ID")

        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        #expect(reopened.room(id: "ROOM:104")?.scoutName == "Alexander Aldridge", "the rename is on disk")
        #expect(reopened.room(id: "ROOM:104-2")?.name == "104")
    }

    @Test func aBoardMovesWithItsRoomWhenTheRoomIsRenamed() throws {
        try seat("104", finalYouth(6), chair: chairOfEither, member(1), member(2))
        try event.startReview(scoutID: finalYouth(6))
        let clockBefore = event.scout(id: finalYouth(6))?["LastUpdateTime"]

        try event.renameRoom(id: "ROOM:104", to: "Library")
        #expect(roomOf(finalYouth(6)) == "Library", "the youth moves with the room")
        #expect([chairOfEither, member(1), member(2)].map(adultRoom) == ["Library", "Library", "Library"],
                "and so does every member")
        #expect(event.room(id: "ROOM:104")?.scoutName == "Finnegan Fenwick", "the card still names the youth")
        #expect(status(finalYouth(6)) == .inProgress, "the review carries on")
        #expect(event.scout(id: finalYouth(6))?["LastUpdateTime"] == clockBefore, "and its timer was not restarted")
        refused("the renamed room is still occupied") { try seat("Library", finalYouth(7), chair: finalChair2, member(3), member(4)) }
        refused("its adults are still committed") { try seat("105", finalYouth(7), chair: chairOfEither, member(3), member(4)) }

        try event.completeBoard(scoutID: finalYouth(6), result: .approved, notes: "")
        #expect(busyAdults == 0, "completing releases every member, none stranded on the old name")
        #expect(event.room(id: "ROOM:104")?.isFree == true)
    }

    @Test func aRoomCannotBeRenamedToSomethingItCannotBe() throws {
        refused("an empty name") { try event.renameRoom(id: "ROOM:104", to: "  ") }
        refused("a name with a comma") { try event.renameRoom(id: "ROOM:104", to: "104, east") }
        refused("a name another room has") { try event.renameRoom(id: "ROOM:104", to: "105") }
        refused("N/A, which marks adults who have gone home") { try event.renameRoom(id: "ROOM:104", to: disabledForTodayMarker) }
        refused("a room that does not exist") { try event.renameRoom(id: "ROOM:nope", to: "999") }
        refused("nor can a room be added as N/A") { try event.addRoom(named: disabledForTodayMarker, boardType: .finalBoard) }
        refused("in any case") { try event.addRoom(named: "n/a", boardType: .finalBoard) }
        try event.renameRoom(id: "ROOM:104", to: "104")
        #expect(event.room(id: "ROOM:104")?.name == "104", "renaming to its own name changes nothing")
        #expect(event.rooms.count == 12)
    }

    /// Windows' ARoomCanBeAddedUnderTheNameARenamedRoomGaveUp: rooms are told
    /// apart by name, and an ID a renamed room kept is not given out again.
    @Test func aRoomCanBeAddedUnderTheNameARenamedRoomGaveUp() throws {
        try event.renameRoom(id: "ROOM:104", to: "110")
        #expect(try event.addRoom(named: "104", boardType: .finalBoard) == "ROOM:104-2")
        refused("a second 104") { try event.addRoom(named: "104", boardType: .finalBoard) }
        refused("a second 110, though no room has the ID ROOM:110") { try event.addRoom(named: "110", boardType: .finalBoard) }
        refused("nor a rename onto it") { try event.renameRoom(id: "ROOM:105", to: "110") }
        #expect(event.rooms.filter { $0.name == "110" }.map(\.id) == ["ROOM:104"])
    }

    /// Undo of Remove Room, and Redo of Add Room, put the record back with
    /// its own ID, so the next Undo or Redo finds it again.
    @Test func aRemovedRoomComesBackUnderItsOwnID() throws {
        try event.renameRoom(id: "ROOM:104", to: "110")
        let removed = try #require(event.room(id: "ROOM:104"))
        try event.removeRoom(id: removed.id)
        try event.restoreRoom(removed)
        #expect(event.room(id: "ROOM:104")?.name == "110" && event.room(id: "ROOM:104")?.boardType == .finalBoard)
        #expect(refusal { try event.restoreRoom(removed) } == "There's already a room 110. Rename or remove it first.")

        try event.removeRoom(id: removed.id)
        try event.addRoom(named: "104", boardType: .projectReview)  // takes the free ROOM:104
        #expect(refusal { try event.restoreRoom(removed) }
            == "Room 104 has taken its place since. Add room 110 by hand instead.")
    }

    /// The room refusals say what to do, in the Add Room and Rename sheets'
    /// own word for it, name.
    @Test func roomRefusalsSayWhatToDo() throws {
        #expect(refusal { try event.addRoom(named: "101", boardType: .finalBoard) }
            == "There's already a room 101. Choose another name.")
        #expect(refusal { try event.renameRoom(id: "ROOM:104", to: "105") } == "There's already a room 105. Choose another name.")
        #expect(refusal { try event.renameRoom(id: "ROOM:104", to: "104, east") }
            == "A room name can't contain a comma. Leave the comma out.")
        #expect(refusal { try event.addRoom(named: disabledForTodayMarker, boardType: .finalBoard) }
            == "N/A marks adults who have gone home. Choose another name.")
        #expect(refusal { try event.addRoom(named: " ", boardType: .finalBoard) } == "Enter a room name.")

        // Undo of Add Room, once a board has taken the room.
        let added = try event.addRoom(named: "108", boardType: .finalBoard)
        try seat("108", finalYouth(1), chair: chairOfEither, member(1), member(2))
        #expect(refusal { try event.removeRoom(id: added) }
            == "Room 108 has a board in it. Complete, reset, or move that board first.")
        #expect(BoardEvent.roomHasABoard("108") == refusal { try event.removeRoom(id: added) }, "as the Room menu says it")
        #expect(refusal { try seat("108", finalYouth(2), chair: finalChair2, member(3), member(4)) }
            == "Room 108 already has Alexander Aldridge's board. Choose a free room.")
    }

    // Java section 14. Here the ids are an array, so the comma never split
    // one; what went wrong was the restart. The files store ',' as '~', so
    // the adult came back under a different id and signing in again made a
    // second person.
    @Test func aNameWithACommaInIt() throws {
        let form = [
            "Last": "Whitmore, Jr.", "First": "Lysander", "Email": "a31@example.org",
            "UnitType": "Troop", "Unit": "2031", "ProjectReview": "Member", "FinalBoard": "Member",
        ]
        try event.registerAdult(form)
        let junior = "ADULT:Whitmore~ Jr.:Lysander:2031"
        #expect(event.adult(id: junior) != nil, "their id carries no comma")
        try seat("101", finalYouth(7), chair: chairOfEither, member(1), junior)
        #expect(adultRoom(junior) == "101")

        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        #expect(reopened.adult(id: junior)?.room == "101", "and are the same person after a restart")
        try reopened.registerAdult(form)
        #expect(reopened.adults.filter { $0.first == "Lysander" }.count == 1, "signing in again does not make a second one")
        try reopened.startReview(scoutID: finalYouth(7))
        try reopened.completeBoard(scoutID: finalYouth(7), result: .approved, notes: "")
        #expect(reopened.adult(id: junior)?.room == "")
    }

    // Java section 15 (two operators seating the same chair at once) has no
    // counterpart: BoardEvent is @MainActor, so every change runs one at a time.

    // Java section 16.
    @Test func theAppRestartsInTheMiddleOfTheEvent() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        try event.startReview(scoutID: finalYouth(1))
        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))

        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        #expect(reopened.scouts.count == event.scouts.count, "no youth lost or duplicated")
        #expect(reopened.adults.count == event.adults.count, "no adult lost or duplicated")
        #expect(reopened.scout(id: finalYouth(1))?.status == .inProgress)
        #expect(reopened.scout(id: finalYouth(2))?.status == .seated)
        #expect(reopened.adults.filter(\.isOnBoard).count == 6)
        #expect(throws: EventError.self, "a committed chair still cannot be double-booked") {
            try reopened.seatBoard(roomID: "ROOM:103", scoutID: finalYouth(3), chairID: chairOfEither,
                                   memberIDs: [chairOfEither, member(5), member(6)])
        }
        try reopened.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "")
        try reopened.startReview(scoutID: finalYouth(2))
        try reopened.completeBoard(scoutID: finalYouth(2), result: .approved, notes: "")
        #expect(reopened.adults.filter(\.isOnBoard).isEmpty)
    }

    // Java section 17. A room's type steers the Seat Board sheet only; the
    // size and chair rules and the timers follow the youth's board type.
    @Test func aRoomSwitchedBetweenProjectAndFinal() throws {
        try event.setBoardType(.finalBoard, forRoom: "ROOM:201A")
        refused("a Final board of 2 is still refused in a room switched to Final") {
            try seat("201A", finalYouth(1), chair: chairOfEither, member(1))
        }
        try seat("201A", finalYouth(1), chair: chairOfEither, member(1), member(2))

        try event.setBoardType(.projectReview, forRoom: "ROOM:106")
        refused("a Member still cannot chair a project review in a room switched to Project") {
            try seat("106", projectYouth(1), chair: member(3), member(4))
        }
        refused("nor can a Final-only chair") { try seat("106", projectYouth(1), chair: finalChair2, member(3)) }
        try seat("106", projectYouth(1), chair: projectChair1, member(3))

        try event.setBoardType(.projectReview, forRoom: "ROOM:102")
        try seat("102", finalYouth(2), chair: finalChair2, member(5), member(6))  // on purpose, as the sheet allows

        try event.startReview(scoutID: finalYouth(1))
        try event.setBoardType(.projectReview, forRoom: "ROOM:201A")
        try event.setBoardType(.finalBoard, forRoom: "ROOM:106")
        #expect(event.room(named: "201A")?.scoutName == "Alexander Aldridge", "switching a room keeps the board in it")
        #expect(adultRoom(chairOfEither) == "201A")
        #expect(status(finalYouth(1)) == .inProgress)
        #expect(event.scout(id: finalYouth(1))?.boardType == .finalBoard)

        try event.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "")
        try runBoard(projectYouth(1))
        try runBoard(finalYouth(2))
        #expect([finalYouth(1), projectYouth(1), finalYouth(2)].map { event.scout(id: $0)?.boardChairID }
            == [chairOfEither, projectChair1, finalChair2], "every board kept the chair it was seated with")
        #expect(busyAdults == 0)
    }

    // Java section 18. A result corrected on the Results page, whose Result
    // menu offers BoardResult.allCases. The pages show the status, chair and
    // members read-only (SPEC.md P-6); moving a result to the right youth,
    // with its board, is checked here on the record, as the data files and
    // /youth-update still take it.
    @Test func aResultCorrectedOnTheResultsPage() throws {
        #expect(BoardResult.allCases.map(\.rawValue) == ["Approved", "Adjourned", "NotApproved"],
                "results are exactly the board's three decisions; Postponed is a status, not a result")

        // The wrong result clicked.
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        try runBoard(finalYouth(1))
        try editYouth(finalYouth(1)) { $0.result = "NotApproved" }
        #expect(result(finalYouth(1)) == "NotApproved")
        #expect(status(finalYouth(1)) == .completed)
        #expect(event.scout(id: finalYouth(1))?.boardChairID == chairOfEither)
        #expect(busyAdults == 0)

        // The right result on the wrong youth.
        let right = try lateYouth("Esterhazy", "Quentin", unit: 3302)
        let wrong = try lateYouth("Esterbrook", "Quentin", unit: 3303)
        try seat("102", wrong, chair: finalChair2, member(3), member(4))
        try runBoard(wrong)
        let board = try #require(event.scout(id: wrong))
        try editYouth(right) {
            $0.status = .completed
            $0.result = "Approved"
            $0.boardChair = board.boardChair
            $0.boardMembers = board.boardMembers
        }
        try editYouth(wrong) {
            $0.status = .registered
            $0.result = ""
            $0.boardChair = ""
            $0.boardMembers = ""
        }
        #expect(status(right) == .completed && result(right) == "Approved")
        #expect(event.scout(id: right)?.boardChair == board.boardChair)
        #expect(status(wrong) == .registered && result(wrong) == "")
        refused("the reviewed youth cannot be seated again") { try seat("103", right, chair: finalChair3, member(5), member(6)) }
        try seat("103", wrong, chair: finalChair3, member(5), member(6))
        try event.startReview(scoutID: wrong)
        try event.completeBoard(scoutID: wrong, result: .notApproved, notes: "")
        #expect(result(wrong) == "NotApproved" && event.scout(id: wrong)?.boardChairID == finalChair3)
        #expect(result(right) == "Approved")

        // Completed by mistake, when the youth was really sent away unprepared.
        let sent = try lateYouth("Fairweather", "Rupert", unit: 3304)
        try seat("104", sent, chair: chairOfEither, member(1), member(2))
        try runBoard(sent)
        try editYouth(sent) {
            $0.status = .postponed
            $0.result = ""
        }
        #expect(status(sent) == .postponed && result(sent) == "")
        refused("a youth sent away cannot be seated again at that event") { try seat("104", sent, chair: chairOfEither, member(1), member(2)) }
        #expect(busyAdults == 0)
    }

    // Java section 25 (SPEC.md P-6). A table corrects a status, but a board is
    // seated, started, reset and completed only through the Event page's
    // steps, which give it a room and members and take them back.
    @Test func aTableCannotSeatStartOrEndABoard() throws {
        refused("a waiting youth is not seated from a table") { try editYouth(finalYouth(1)) { $0.status = .seated } }
        refused("nor put in review") { try editYouth(finalYouth(1)) { $0.status = .inProgress } }
        #expect(status(finalYouth(1)) == .registered && event.scout(id: finalYouth(1))?.room == "")

        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        refused("a seated board is not sent back to waiting from a table") {
            try editYouth(finalYouth(1)) { $0.status = .registered }
        }
        try event.startReview(scoutID: finalYouth(1))
        refused("nor a review completed") { try editYouth(finalYouth(1)) { $0.status = .completed } }
        refused("nor postponed") { try editYouth(finalYouth(1)) { $0.status = .postponed } }
        try editYouth(finalYouth(1)) { $0.notes = "Strong answers" }
        #expect(event.scout(id: finalYouth(1))?.notes == "Strong answers", "the rest of a sitting board's record still corrects")
        #expect(status(finalYouth(1)) == .inProgress && busyAdults == 3, "and the room and members stay with it")

        try event.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "")
        try editYouth(finalYouth(2)) { $0.status = .postponed }
        #expect(status(finalYouth(2)) == .postponed, "a status that holds no room still corrects")
        #expect(busyAdults == 0)
    }

    // Java section 26 (SPEC.md P-6). An adult's facts are edited on the
    // Adults page and kept in the history, which is read-only: BoardEvent has
    // no call that edits it (Java's /adult-history-update refuses one).
    @Test func aChairPromotedOnTheAdultsPageIsSeatedAsOne() throws {
        #expect(event.adultHistory.first { $0.id == member(1) }?.finalBoardRoleText == "Member")
        refused("a plain member cannot chair") { try seat("101", finalYouth(1), chair: member(1), member(2), member(3)) }
        var promoted = try #require(event.adult(id: member(1)))
        promoted.finalBoardRoleText = BoardRole.chair.rawValue
        promoted.phone = "555-0106"
        promoted.woodBadge = "Y"
        try event.updateAdult(promoted)
        let history = try #require(event.adultHistory.first { $0.id == member(1) })
        #expect(history.canChair(.finalBoard), "and is a chair in the history too, for their next sign-in")
        #expect(history.phone == "555-0106", "their contact follows too")
        #expect(history.woodBadge == "", "but Wood Badge stays with the event")
        try seat("101", finalYouth(1), chair: member(1), member(2), member(3))
        #expect(event.scout(id: finalYouth(1))?.boardChairID == member(1), "the promoted chair is seated as one")
        #expect(event.adult(id: member(1))?.room == "101" && history.room == "", "their room is this event's alone")
    }

    // Mac only, with no Java section: the inspector marks who chairs the
    // board being drawn up and Make Chair hands it on (SPEC.md D-10, D-12).
    // Seat Board seats that chair, not the first on the board who may chair.
    @Test func seatBoardSeatsTheChairMadeInTheInspector() throws {
        let youth = try #require(event.scout(id: finalYouth(1)))
        var drafts = BoardDrafts()
        drafts.select(youth, in: event)
        let proposedChair = try #require(drafts[youth.id]?.chairID)
        let finalChairs = [chairOfEither, finalChair2, finalChair3]
        let other = try #require(finalChairs.first { drafts[youth.id]?.memberIDs.contains($0) == false })
        drafts.add([other], for: youth.id, in: event)
        drafts.makeChair(try #require(event.adult(id: other)), for: youth, in: event)

        let draft = try #require(drafts[youth.id])
        let roomID = try #require(draft.roomID)
        let review = SeatingReview(
            scout: youth, members: draft.memberIDs.compactMap { event.adult(id: $0) }, room: event.room(id: roomID))
        #expect(review.qualifiedChairs.first?.id == proposedChair, "the proposal's chair is still first on the board")
        let chairID = try #require(draft.chairToSeat(from: review.qualifiedChairs))
        #expect(chairID == other)

        try event.seatBoard(roomID: roomID, scoutID: youth.id, chairID: chairID, memberIDs: draft.memberIDs)
        #expect(event.scout(id: youth.id)?.boardChairID == other)
        #expect(adultRoom(proposedChair) == event.room(id: roomID)?.name, "the proposal's chair sits as a member")
        drafts.discard(youth.id)
        drafts.refresh(selected: event.scout(id: youth.id), in: event)
        #expect(drafts[youth.id] == nil, "a seated youth has no board drawn up")
    }

    // Java section 27. Add Adult, for someone who won't use the tablet, signs
    // them in as the tablet does; filled in from the adult history it carries
    // that record's ID, so a name corrected in the sheet is the same adult.
    @Test func anAdultSignedInByHandFromTheHistory() throws {
        try event.registerAdult([
            "Last": "Handley", "First": "Harriet", "Email": "hh@example.org", "UnitType": "Troop", "Unit": "3601",
            "ProjectReview": "Member", "FinalBoard": "Chair",
        ])
        let hand = "ADULT:Handley:Harriet:3601"
        try event.deleteAdult(id: hand)
        #expect(event.adult(id: hand) == nil, "an adult taken off the event's list")
        let historyCount = event.adultHistory.count
        let back = try event.registerAdult(Adult.handSignInForm(
            historyID: hand, first: "Harriet Ann", last: "Handley", email: "hh@example.org", phone: "",
            unitType: "Troop", unit: "3601", finalBoard: .chair, projectReview: .member, woodBadge: false
        ))
        #expect(back.id == hand && back.first == "Harriet Ann", "is signed in by hand as the same adult")
        #expect(back.canChair(.finalBoard), "still a chair")
        #expect(event.adultHistory.count == historyCount, "with no second history record")
        #expect(event.adultHistory.first { $0.id == hand }?.first == "Harriet Ann", "and the corrected name in the history")
    }

    // Java section 28 (SPEC.md D-22). Approved proposals from earlier events,
    // for a youth who comes without the signed page: every dated folder
    // before this event, however long ago; only Project rows whose Result is
    // Approved; read afresh each time, nothing written; and never a
    // birthdate, phone number or email.
    @Test func approvedProposalsFromEarlierEvents() throws {
        let header = "Type,ID,RegNum,Last,First,Email,Phone,UnitType,Unit,UnitName,DOB,BoardType,Leader,RegTime,"
            + "LastUpdateTime,Flags,Room,Status,Result,BoardChair,BoardChairID,BoardMembers,BoardMembersIDs,Notes\n"
        func row(_ last: String, _ first: String, _ unit: Int, _ type: String, _ result: String, chair: String = "Chris Chair",
                 notes: String = "") -> String {
            "SCOUT,SCOUT:\(last):\(first):\(unit),W1,\(last),\(first),\(first.lowercased())@example.org,555-0199,Troop,\(unit),"
                + "Troop\(unit),1/2/2010,\(type),,,,,N/A,Completed,\(result),\(chair),ADULT:Chair:Chris:1,"
                + "\(chair)~Morgan Member,ADULT:Chair:Chris:1~ADULT:Member:Morgan:2,\(notes)\n"
        }
        #expect(event.approvedProposals().summary == "No earlier events in this data folder.")

        try scratch.write(header + row("Quill", "Ada", 3701, "Project", "Approved", notes: "Park benches~ phase one"),
                          to: "2019-05-28/scouts.csv")
        try scratch.write(header + row("Brook", "Ben", 3702, "Project", "Approved")
                          + row("Final", "Fay", 3703, "Final", "Approved")
                          + row("Later", "Lou", 3704, "Project", "Adjourned"),
                          to: "2026-08-25/scouts.csv")
        try scratch.write(header + row("Future", "Flo", 3705, "Project", "Approved"), to: "2026-10-27/scouts.csv")
        try scratch.write(header + row("Undated", "Una", 3706, "Project", "Approved"), to: "notes/scouts.csv")
        // A folder whose youth file can't be read: here a folder in its place.
        try FileManager.default.createDirectory(at: scratch.url.appending(path: "2026-07-28/scouts.csv"),
                                                withIntermediateDirectories: true)
        // And a dated folder with no youth file, which held no event.
        try FileManager.default.createDirectory(at: scratch.url.appending(path: "2020-01-01"), withIntermediateDirectories: true)

        let found = event.approvedProposals()
        #expect(found.approvals.map(\.last) == ["Brook", "Quill"], "earlier events only, approved proposals only, by last name")
        #expect(found.summary == "Read from 2 earlier events, 2019-05-28 to 2026-08-25.", "however long ago")
        let us = Locale(identifier: "en_US")
        #expect(found.shownSummary(locale: us) == "Read from 2 earlier events, May 28, 2019 to August 25, 2026.",
                "the page shows the dates as the Mac writes them")
        #expect(found.unreadable.map(\.event) == ["2026-07-28"], "a folder that can't be read is named")
        let unreadable = try #require(found.unreadable.first)
        #expect(unreadable.shownLine(locale: us) == "Could not read the July 28, 2026 event: \(unreadable.reason)")
        #expect(!unreadable.reason.isEmpty)
        let ada = try #require(found.approvals.last)
        #expect(ada.event == "2019-05-28" && ada.unit == "Troop 3701" && ada.chair == "Chris Chair")
        #expect(ada.otherMembers == ["Morgan Member"] && ada.notes == "Park benches, phase one")
        let shown = String(describing: found.approvals)
        #expect(!shown.contains("@example.org") && !shown.contains("555-0199") && !shown.contains("1/2/2010"),
                "never an email, a phone number or a birthdate (D-7, D-8)")

        try scratch.write(header + row("Brook", "Ben", 3702, "Project", "Approved")
                          + row("Cove~ Jr.", "Cal", 3707, "Project", "Approved", chair: "Chris Chair~ Sr."),
                          to: "2026-08-25/scouts.csv")
        let reread = event.approvedProposals().approvals
        #expect(reread.map(\.last) == ["Brook", "Cove, Jr.", "Quill"], "read afresh each time")
        #expect(reread[1].chair == "Chris Chair, Sr.", "and shown with the commas the file kept as ~ (D-1)")
        #expect(try scratch.text("2019-05-28/scouts.csv").contains("555-0199"), "and nothing in an earlier folder is written")
        #expect(!FileManager.default.fileExists(atPath: scratch.url.appending(path: "2020-01-01/scouts.csv").path),
                "not even a youth file where there was none")
    }

    // Java section 19. What an adult says at sign-in.
    @Test func woodBadgeNoThanksAndTheYouthAnAdultCameToSupport() throws {
        let rsvp = try lateYouth("Galloway", "Tobias", unit: 3401)
        var form = [
            "Last": "Hargrove", "First": "Ines", "Email": "a41@example.org", "UnitType": "Troop", "Unit": "3401",
            "ProjectReview": "Member", "FinalBoard": "Member",
            "WoodBadge": "Y", "Supporting": "\(rsvp)|SCOUT:Nobody:Here:0",
        ]
        try event.registerAdult(form)
        let leader = "ADULT:Hargrove:Ines:3401"
        #expect(event.adult(id: leader)?.woodBadge == "Y", "Wood Badge is recorded")
        #expect(event.adult(id: leader)?.supporting == "\(rsvp)|SCOUT:Nobody:Here:0", "and whom they came to support")
        let history = try #require(event.adultHistory.first { $0.id == leader })
        #expect(history.woodBadge.isEmpty && history.supporting.isEmpty, "neither is kept for next month")

        form["WoodBadge"] = "yes"
        form["Supporting"] = ""
        try event.registerAdult(form)
        #expect(event.adult(id: leader)?.supporting == "", "signing in again says what is true now")
        #expect(event.adult(id: leader)?.woodBadge == "", "and Wood Badge is Y or nothing")

        // "No thanks" is stored as Unavailable; Seat Board refuses them there.
        try event.registerAdult([
            "Last": "Ibarra", "First": "Juno", "Email": "a42@example.org", "UnitType": "Troop", "Unit": "3402",
            "ProjectReview": "Unavailable", "FinalBoard": "Member",
        ])
        let noProject = "ADULT:Ibarra:Juno:3402"
        #expect(event.adult(id: noProject)?.projectReviewRoleText == "Unavailable")
        let project = try lateYouth("Jaramillo", "Kai", unit: 3403, "Project")
        refused("they are not seated on a proposal review") { try seat("200A", project, chair: projectChair1, noProject) }
        #expect(busyAdults == 0)
        try seat("101", rsvp, chair: chairOfEither, member(1), noProject)  // a Final board is fine
        try event.resetBoard(scoutID: rsvp)

        // The sign-in list: RSVPs not yet here, and this event's youth who are
        // not done yet.
        try CSVFile.write([Scout(fields: [
            "Type": "SCOUT", "ID": "SCOUT:Rsvp:Only:3999", "Last": "Rsvp", "First": "Only",
            "UnitType": "Troop", "Unit": "3999", "BoardType": "Final",
        ])], to: scratch.dataFolder.scheduledYouthURL(event: "2026-09-22"))
        try event.postponeBoard(scoutID: finalYouth(9))
        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        let choices = reopened.scoutChoices().map(\.id)
        #expect(choices.contains("SCOUT:Rsvp:Only:3999"), "an RSVP not yet signed in can be chosen")
        #expect(choices.contains(rsvp), "so can someone signed in at this event")
        #expect(!choices.contains(finalYouth(9)), "but not someone done for the event")
    }

    // Java section 19, linking after both have signed in.
    @Test func anOperatorLinksAnAdultToAYouthAfterBothSignedIn() throws {
        try event.setSupporting(true, adultID: member(1), scoutID: finalYouth(1))
        #expect(event.adult(id: member(1))?.supporting == finalYouth(1))
        try event.setSupporting(true, adultID: member(1), scoutID: finalYouth(1))
        #expect(event.adult(id: member(1))?.supporting == finalYouth(1), "pressing it twice links once")

        try seat("101", finalYouth(1), chair: chairOfEither, member(2), member(3))
        try runBoard(finalYouth(1))
        #expect(event.adult(id: member(1))?.supporting == finalYouth(1), "the link survives the youth's board")

        try event.setSupporting(false, adultID: member(1), scoutID: finalYouth(1))
        #expect(event.adult(id: member(1))?.supporting == "", "and can be undone")

        refused("an unknown adult") { try event.setSupporting(true, adultID: "ADULT:Nobody:Here:0", scoutID: finalYouth(2)) }
        refused("an unknown youth") { try event.setSupporting(true, adultID: member(1), scoutID: "SCOUT:Nobody:Here:0") }
        try event.setSupporting(false, adultID: member(1), scoutID: "SCOUT:Nobody:Here:0")  // clearing a stale link is fine
    }

    // SPEC.md D-23. Start Review on a board of review names whoever
    // introduces the youth, and where they are now.
    @Test func startReviewNamesWhoIntroducesTheYouthAndWhereTheyAre() throws {
        try event.registerAdult([
            "Last": "Scoutmaster", "First": "Sam", "Email": "sm@example.org", "UnitType": "Troop", "Unit": "1001",
            "ProjectReview": "Member", "FinalBoard": "Member", "Supporting": finalYouth(1),
        ])
        let scoutmaster = "ADULT:Scoutmaster:Sam:1001"
        try seat("102", finalYouth(2), chair: finalChair2, member(3), scoutmaster)  // sitting on another board
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        let youth = try #require(event.scout(id: finalYouth(1)))
        let introducers = try #require(AdultLocator.introduction(for: youth, among: event.adults))
        #expect(introducers.map(\.adult.id) == [scoutmaster] && introducers.map(\.relation) == [.supporting])
        #expect(AdultLocator.introductionText(for: youth, among: event.adults)
            == "\n\nFirst fetch whoever introduces them to the board:\nSam Scoutmaster (Room 102)",
            "so someone can fetch them from their board")

        try runBoard(finalYouth(2))
        #expect(AdultLocator.introduction(for: youth, among: event.adults)?.first?.whereabouts == "Main room",
                "off a board, they are in the main room")
        try event.setAvailable(false, adultID: scoutmaster)
        #expect(AdultLocator.introduction(for: youth, among: event.adults)?.first?.whereabouts == "marked as gone home")
    }

    // SPEC.md D-23 and O-2. A project review has no introduction, so the Mac
    // starts it at once, as Windows does, and Undo is the way back: even with
    // an adult linked to the youth there is no one to fetch, and restoreBoard
    // returns the board to convening in its room with its timer as it was.
    @Test func aProjectReviewStartsAtOnceAndUndoTakesItBack() throws {
        try event.registerAdult([
            "Last": "Scoutmaster", "First": "Sam", "Email": "sm@example.org", "UnitType": "Troop", "Unit": "1010",
            "ProjectReview": "Member", "FinalBoard": "Member", "Supporting": projectYouth(1),
        ])
        try seat("200A", projectYouth(1), chair: projectChair1, member(1))
        let seated = try #require(event.scout(id: projectYouth(1)))
        #expect(AdultLocator.introduction(for: seated, among: event.adults) == nil, "no reminder to confirm")

        try event.startReview(scoutID: projectYouth(1))
        #expect(status(projectYouth(1)) == .inProgress)
        try event.restoreBoard(seated)
        #expect(status(projectYouth(1)) == .seated)
        #expect(event.scout(id: projectYouth(1))?.lastUpdateTime == seated.lastUpdateTime, "the convening timer resumes")
        #expect(roomOf(projectYouth(1)) == "200A" && adultRoom(projectChair1) == "200A" && adultRoom(member(1)) == "200A")
    }

    // Java section 24, the youth phone number (SPEC.md D-8), which goes the
    // way the birthdate did (D-7, O-5): not kept from a sign-in or an import,
    // but one already on file stays there, never shown or exported. An
    // adult's number is kept as before.
    //
    // What the tablet is sent belongs to the check-in server, a module these
    // tests do not link: CheckInServerTests signs the same youth and adult in
    // over HTTP and reads the lookups back
    // (aYouthsPhoneNumberIsNotKeptButAnAdultsStillFillsTheirForm,
    // lookupsFillTheFormAndNothingMore). The Java grid, CSV, filter and
    // autofill reads (the -cells endpoints, /youth-autofill) cannot arise:
    // this server has none, and operatorPagesAndRecordsAreNotReachable
    // asserts each is a 404. Their counterparts here are the lists exported
    // from the View pages and the board results report, checked below.
    // The section's three autofill checks (Java 41860ef, Windows 0069199)
    // cannot arise either. The old autofill lists no adult's email and no
    // pre-registered youth's, because neither /adult-autofill nor
    // /youth-autofill is served (the same 404 test). A lookup for an
    // address the tablet is given is still answered, by POST
    // /api/youth-lookup and /api/adult-lookup, which
    // lookupsFillTheFormAndNothingMore checks with a mixed-case address.
    // The Youth and Pre-Registered pages show no phone number and do not
    // search one, so neither has a filter that could say whose number it is.
    @Test func aYouthsPhoneNumberIsNotKeptButOneOnFileStays() throws {
        // A pre-registration given a birthdate and a phone number by hand, as
        // a file from before D-7 and D-8 would have them.
        try event.mergeSignUps([
            SignUpEntry(startDate: "2026-09-22 19:00", firstName: "lena", lastName: "lookup", item: "Eagle Board of Review",
                        email: "Lena.Lookup@Example.org", customAnswers: ["Troop 4401", "555-0100", ""]),
        ], month: "2026-09")
        var lena = try #require(event.scheduledYouth(matchingEmail: "  lena.lookup@EXAMPLE.org "))
        #expect(lena.phone == "", "SignUpGenius puts no phone number on a youth")
        lena.dateOfBirth = "2010-05-06"
        lena.phone = "555-0100"
        try event.updateYouth(lena, scheduled: true)
        let scheduledFile = try scratch.text("2026-09-22/scouts_scheduled.csv")
        #expect(scheduledFile.contains("555-0100") && scheduledFile.contains("2010-05-06"), "both stay on file")
        let scheduledList = CSVFile.render(event.scheduledScouts.map(\.forExport))
        #expect(!scheduledList.contains("555-0100") && !scheduledList.contains("2010-05-06"),
                "but the pre-registrations exported from the Pre-Registered page leave them out")

        // A new sign-in from an old cached page.
        var form = [
            "Last": "Oldpage", "First": "Olive", "Email": "op@example.org", "Phone": "555-0101",
            "UnitType": "Troop", "Unit": "4402", "BoardType": "Final", "DOB": "2011-02-03",
        ]
        try event.registerYouth(form)
        let olive = "SCOUT:Oldpage:Olive:4402"
        func onFile() throws -> String {
            let youth = try #require(CSVFile.read(Scout.self, from: scratch.dataFolder.youthURL(event: "2026-09-22"))
                .first(where: { $0.id == olive }))
            return "\(youth.dateOfBirth)|\(youth.phone)"
        }
        #expect(try onFile() == "|", "neither a birthdate nor a phone number from an old cached page is kept")

        try editYouth(olive) {
            $0.dateOfBirth = "2011-02-03"
            $0.phone = "555-0101"
        }
        #expect(try onFile() == "2011-02-03|555-0101", "one already on file stays on file")
        let report = Reports.csv(event.scouts, columns: Reports.boardResultColumns)
        #expect(!report.contains("2011-02-03") && !report.contains("555-0101"), "but the board results report never shows it")
        let youthList = CSVFile.render(event.scouts.map(\.forExport))
        #expect(!youthList.contains("2011-02-03") && !youthList.contains("555-0101"), "nor a list exported from the Youth page")
        #expect(CSVFile.parse(Scout.self, text: youthList).first(where: { $0.id == olive })?.first == "Olive",
                "which keeps the columns, so they still line up")

        form["Phone"] = "555-0199"
        form["DOB"] = "2012-12-12"
        try event.registerYouth(form)
        #expect(try onFile() == "2011-02-03|555-0101", "and signing in again neither changes nor blanks it")

        // An adult's number is kept, at this event and in the history the adult
        // lookup reads.
        try event.registerAdult([
            "Last": "Phoneon", "First": "Adele", "Email": "adele@example.org", "Phone": "555-0102",
            "UnitType": "Troop", "Unit": "4403", "ProjectReview": "Member", "FinalBoard": "Member",
        ])
        #expect(event.adult(id: "ADULT:Phoneon:Adele:4403")?.phone == "555-0102")
        #expect(event.knownAdult(matchingEmail: "adele@example.org")?.phone == "555-0102")
    }

    // MARK: - Undo
    //
    // Java section 20, these two. Its refusal after an Admin-page edit to the
    // same field has no counterpart here: no table edits a board's chair or
    // members (SPEC.md P-6), and restoreBoard refuses on the room and the
    // members instead. Its undo of a Disable is section 4's
    // anAdultWhoLeavesIsOutUntilReEnabled: Undo applies the inverse
    // setAvailable, which that test runs both ways.
    //
    // Java section 22 (the browser Event page told of changes over /events,
    // and the check-in address and QR code it shows) is Java's alone: the
    // Mac's operator screen is native and observes BoardEvent directly
    // (D-15), and operatorPagesAndRecordsAreNotReachable checks that those
    // paths are not served.

    /// Undo of each step is restoreBoard with the record from before it.
    @Test func eachStepIsUndoneAndRedone() throws {
        let waiting = try #require(event.scout(id: finalYouth(1)))
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        let seated = try #require(event.scout(id: finalYouth(1)))

        try event.restoreBoard(waiting)
        #expect(status(finalYouth(1)) == .registered)
        #expect(roomOf(finalYouth(1)) == "")
        #expect(adultRoom(chairOfEither) == "")
        #expect(event.room(named: "101")?.isFree == true)

        try event.restoreBoard(seated)
        #expect(status(finalYouth(1)) == .seated)
        #expect(adultRoom(member(2)) == "101")
        #expect(event.room(named: "101")?.scoutName == seated.fullName)

        try event.startReview(scoutID: finalYouth(1))
        let inReview = try #require(event.scout(id: finalYouth(1)))
        try event.restoreBoard(seated)
        #expect(status(finalYouth(1)) == .seated)
        #expect(event.scout(id: finalYouth(1))?.lastUpdateTime == seated.lastUpdateTime, "the convening timer resumes")
        try event.restoreBoard(inReview)

        try event.completeBoard(scoutID: finalYouth(1), result: .adjourned, notes: "Come back next month")
        #expect(adultRoom(chairOfEither) == "")
        try event.restoreBoard(inReview)
        #expect(status(finalYouth(1)) == .inProgress)
        #expect(event.scout(id: finalYouth(1))?.result == "")
        #expect(event.scout(id: finalYouth(1))?.notes == "")
        #expect(adultRoom(chairOfEither) == "101", "the members are back on the board")
        #expect(event.room(named: "101")?.isFree == false)

        try event.resetBoard(scoutID: finalYouth(1))
        try event.restoreBoard(inReview)
        #expect(status(finalYouth(1)) == .inProgress)
        #expect(adultRoom(member(1)) == "101")

        let other = try #require(event.scout(id: finalYouth(2)))
        try event.postponeBoard(scoutID: finalYouth(2))
        try event.restoreBoard(other)
        #expect(status(finalYouth(2)) == .registered)
    }

    /// Undo cannot put anyone on two boards: once the room or a member has
    /// been given to another board, the old board stays as it is.
    @Test func undoIsRefusedOnceTheEventHasMovedOn() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        let seated = try #require(event.scout(id: finalYouth(1)))
        try event.resetBoard(scoutID: finalYouth(1))

        try seat("101", finalYouth(2), chair: finalChair2, member(3), member(4))
        refused("room 101 has another board now") { try event.restoreBoard(seated) }
        #expect(status(finalYouth(1)) == .registered)
        #expect(event.room(named: "101")?.scoutName == event.scout(id: finalYouth(2))?.fullName)

        try event.resetBoard(scoutID: finalYouth(2))
        try seat("102", finalYouth(3), chair: finalChair3, member(1), member(5))
        refused("a member is on another board now") { try event.restoreBoard(seated) }
        #expect(adultRoom(member(1)) == "102")

        try event.resetBoard(scoutID: finalYouth(3))
        try event.setAvailable(false, adultID: member(2))
        refused("a member has gone home") { try event.restoreBoard(seated) }

        try event.setAvailable(true, adultID: member(2))
        try event.restoreBoard(seated)
        #expect(status(finalYouth(1)) == .seated)
    }

    /// Room › Copy Rooms From says which rooms it added, which are what its
    /// Undo removes, so a second copy adding none has nothing to undo.
    @Test func copyRoomsSaysWhichRoomsItAdded() throws {
        try scratch.write("""
            Type,ID,Room,BoardType,Scout,Leaders,RegTime
            ROOM,ROOM:101,101,Final,,,
            ROOM,ROOM:301,301,Final,Old Youth,Old Adults,
            ROOM,ROOM:302,302,Project,,,

            """, to: "2026-08-25/rooms.csv")
        #expect(try event.copyRooms(fromEvent: "2026-08-25") == ["ROOM:301", "ROOM:302"], "101 is here already")
        #expect(event.room(id: "ROOM:301")?.isFree == true, "copied empty")
        #expect(try event.copyRooms(fromEvent: "2026-08-25").isEmpty, "a second copy skips the rooms that exist")
        #expect(event.rooms.count == 14)
    }

    // MARK: - Opening the event

    /// SPEC.md D-9: a data folder with no adult history gets a new, empty
    /// one, and the open that made it says so, for the app to name the path.
    @Test func onlyTheOpenThatStartsTheAdultHistorySaysSo() throws {
        #expect(event.createdAdultHistory, "this scratch folder had none")
        #expect(try !BoardEvent(folder: scratch.dataFolder, date: "2026-09-22").createdAdultHistory, "the next open found it")
        #expect(try !BoardEvent(folder: scratch.dataFolder, date: "2026-10-27").createdAdultHistory, "so does another event's")
    }

    private func seatFiveBoards() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))
        try seat("103", finalYouth(3), chair: finalChair3, member(5), member(6))
        try seat("200A", projectYouth(1), chair: projectChair1, member(7))
        try seat("200B", projectYouth(2), chair: projectChair2, member(8))
    }
}
