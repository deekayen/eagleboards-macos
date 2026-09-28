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
/// night does with them: boards convening and starting, adults committed to
/// one room and released when the review finishes, boards postponed and reset,
/// and the rules holding even for requests that skip the Seat Board sheet.
///
/// Add a case here when you change how a board is seated, run or torn down.
@MainActor
@Suite("A board event")
struct BoardEventTests {
    let scratch: ScratchFolder
    let night: EventNight

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
        night = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")

        for name in ["101", "102", "103", "104", "105", "106", "107"] {
            try night.addRoom(named: name, boardType: .finalBoard)
        }
        for name in ["200A", "200B", "201A", "201B", "202"] {
            try night.addRoom(named: name, boardType: .projectReview)
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
            try night.registerYouth([
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
        try night.registerAdult([
            "Last": adultLastNames[number - 1], "First": adultFirstNames[number - 1],
            "Email": "a\(number)@example.org", "UnitType": "Troop", "Unit": "\(unit)",
            "ProjectReview": project, "FinalBoard": final,
        ])
    }

    // MARK: - Helpers that read the event back

    private func seat(_ roomName: String, _ scoutID: String, chair: String, _ members: String...) throws {
        try night.seatBoard(roomID: "ROOM:\(roomName)", scoutID: scoutID, chairID: chair, memberIDs: [chair] + members)
    }

    private func refused(_ what: Comment, _ action: () throws -> Void) {
        #expect(throws: EventError.self, what, performing: action)
    }

    private func count(_ status: BoardStatus) -> Int { night.scouts.filter { $0.status == status }.count }
    private var busyAdults: Int { night.adults.filter(\.isOnBoard).count }
    private var emptyRooms: Int { night.rooms.filter(\.isFree).count }
    private func status(_ scoutID: String) -> BoardStatus? { night.scout(id: scoutID)?.status }
    private func roomOf(_ scoutID: String) -> String? { night.scout(id: scoutID)?.room }
    private func adultRoom(_ adultID: String) -> String? { night.adult(id: adultID)?.room }

    private func runBoard(_ scoutID: String) throws {
        try night.startReview(scoutID: scoutID)
        try night.completeBoard(scoutID: scoutID, result: .approved, notes: "")
    }

    // MARK: - The event

    @Test func theEventAsSeeded() {
        #expect(night.rooms.count == 12)
        #expect(night.adults.count == 30)
        #expect(night.scouts.count == 14)
        #expect(night.adults.filter { $0.canChair(.finalBoard) || $0.canChair(.projectReview) }.count == 5)
    }

    @Test func compositionRulesHoldWithoutTheSeatBoardSheet() {
        refused("a Final board of 2 (GTA 8.0.0.3 floor)") { try seat("101", finalYouth(1), chair: chairOfEither, member(1)) }
        refused("a Final board of 7 (GTA 8.0.0.3 ceiling)") { try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2), member(3), member(4), member(5), member(6)) }
        refused("a project review of 1") { try seat("200A", projectYouth(1), chair: projectChair1) }
        refused("a project review of 7") { try seat("200A", projectYouth(1), chair: projectChair1, member(1), member(2), member(3), member(4), member(5), member(6)) }

        refused("a plain Member may not chair a Final board") { try seat("101", finalYouth(1), chair: member(1), member(2), member(3)) }
        refused("a Project chair may not chair a Final board") { try seat("101", finalYouth(1), chair: projectChair1, member(1), member(2)) }
        refused("a plain Member may not chair a project review") { try seat("200A", projectYouth(1), chair: member(1), member(2)) }
        refused("the chair must be sitting on the board") {
            try night.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: finalChair2, memberIDs: [member(1), member(2), member(3)])
        }
        refused("an unknown chair") {
            try night.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: "NOBODY", memberIDs: [member(1), member(2), member(3)])
        }
        refused("a board with no members") {
            try night.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [])
        }
        refused("the same member listed twice does not make a board of three") {
            try night.seatBoard(roomID: "ROOM:101", scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(1), member(1)])
        }

        #expect(count(.seated) == 0, "none of that seated anyone")
        #expect(busyAdults == 0)
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
        try night.setAvailable(false, adultID: member(11))
        #expect(adultRoom(member(11)) == disabledForTonightMarker)
        refused("a disabled adult cannot be seated") { try seat("104", finalYouth(4), chair: chairOfEither, member(11), member(12)) }
        refused("an adult on a board cannot be disabled") { try night.setAvailable(false, adultID: member(1)) }

        try night.setAvailable(true, adultID: member(11))
        #expect(adultRoom(member(11)) == "")
    }

    @Test func conveneThenReviewThenComplete() throws {
        try seatFiveBoards()
        refused("a result cannot be recorded while the board is still convening") {
            try night.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "")
        }
        #expect(status(finalYouth(1)) == .seated)

        try night.startReview(scoutID: finalYouth(1))
        #expect(status(finalYouth(1)) == .inProgress)
        refused("a review cannot be started twice") { try night.startReview(scoutID: finalYouth(1)) }

        try night.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "Well prepared, thorough workbook")
        #expect(status(finalYouth(1)) == .completed)
        #expect(night.scout(id: finalYouth(1))?.result == "Approved")
    }

    @Test func completingAReviewReleasesItsAdults() throws {
        try seatFiveBoards()
        try runBoard(finalYouth(1))
        #expect(adultRoom(chairOfEither) == "")
        #expect(adultRoom(member(1)) == "")
        #expect(adultRoom(member(2)) == "")
        #expect(busyAdults == 10)
        #expect(night.room(named: "101")?.isFree == true)

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
        let seated = try #require(night.scout(id: finalYouth(1)))

        refused("only a seated or in-review board can have its members changed") {
            try night.changeMembers(scoutID: finalYouth(2), chairID: finalChair2, memberIDs: [finalChair2, member(3)])
        }

        try night.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(1), member(3)])
        let changed = try #require(night.scout(id: finalYouth(1)))
        #expect(changed.status == .seated, "still seated, not reseated")
        #expect(changed.lastUpdateTime == seated.lastUpdateTime, "the room timer keeps running")
        #expect(changed.boardMemberIDs.split(separator: ",").count == 3)
        #expect(adultRoom(member(2)) == "", "dropped off the board, freed")
        #expect(adultRoom(member(3)) == "101", "added to the board")
        #expect(night.room(named: "101")?.leaderNames == changed.boardMembers)

        try seat("102", finalYouth(2), chair: finalChair2, member(4), member(9))
        refused("a member already on another board cannot be added") {
            try night.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(4)])
        }

        try night.startReview(scoutID: finalYouth(1))
        let inReview = try #require(night.scout(id: finalYouth(1)))
        try night.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither, member(1), member(2)])
        #expect(status(finalYouth(1)) == .inProgress, "changing members mid-review does not end it")
        #expect(night.scout(id: finalYouth(1))?.lastUpdateTime == inReview.lastUpdateTime, "the review timer keeps running too")

        refused("the chair must stay one of the members") {
            try night.changeMembers(scoutID: finalYouth(1), chairID: member(5), memberIDs: [chairOfEither, member(1), member(2)])
        }
        refused("a board of one is below the Final minimum") {
            try night.changeMembers(scoutID: finalYouth(1), chairID: chairOfEither, memberIDs: [chairOfEither])
        }

        try night.restoreBoard(inReview)
        #expect(adultRoom(member(3)) == "101", "back on the board after undo, as it was mid-review")
        #expect(adultRoom(member(2)) == "", "not on the board being restored to, so freed by the undo")
        #expect(adultRoom(member(1)) == "101")
        #expect(night.scout(id: finalYouth(1))?.boardMemberIDs.split(separator: ",").count == 3)
    }

    /// Java event test section 21, the cases the test above leaves out: the
    /// chair leaving and another chair taking over, a plain member refused
    /// the chair, and Complete releasing whoever sits on the board by then.
    @Test func changeMembersHandsTheChairOnAndCompleteReleasesTheNewBoard() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))

        try night.changeMembers(scoutID: finalYouth(1), chairID: finalChair3, memberIDs: [finalChair3, member(1), member(3)])
        #expect(adultRoom(chairOfEither) == "", "the chair who left is free")
        #expect(adultRoom(member(2)) == "", "the member not kept is free")
        #expect(adultRoom(finalChair3) == "101" && adultRoom(member(3)) == "101", "the new chair and member are in the room")
        #expect(night.scout(id: finalYouth(1))?.boardChairID == finalChair3, "the new chair is recorded")

        refused("a plain member may not take the chair") {
            try night.changeMembers(scoutID: finalYouth(1), chairID: member(1), memberIDs: [finalChair3, member(1), member(3)])
        }
        #expect(night.scout(id: finalYouth(1))?.boardChairID == finalChair3, "the refusal changed nothing")

        try runBoard(finalYouth(1))
        #expect(adultRoom(finalChair3) == "" && adultRoom(member(1)) == "" && adultRoom(member(3)) == "",
                "completing releases the board as changed")
        #expect(busyAdults == 0)
    }

    @Test func postponeAndReset() throws {
        try seatFiveBoards()
        try night.postponeBoard(scoutID: finalYouth(9))
        #expect(status(finalYouth(9)) == .postponed)

        refused("a youth whose board has convened cannot be postponed") { try night.postponeBoard(scoutID: finalYouth(2)) }
        #expect(status(finalYouth(2)) == .seated)

        let busyBefore = busyAdults
        try night.resetBoard(scoutID: finalYouth(2))
        #expect(status(finalYouth(2)) == .registered)
        #expect(roomOf(finalYouth(2)) == "")
        #expect(adultRoom(finalChair2) == "")
        #expect(busyAdults == busyBefore - 3, "the chair and both members are released")

        try night.startReview(scoutID: projectYouth(1))
        try night.resetBoard(scoutID: projectYouth(1))
        #expect(status(projectYouth(1)) == .registered)
        #expect(adultRoom(projectChair1) == "")

        refused("a waiting youth has nothing to reset") { try night.resetBoard(scoutID: finalYouth(2)) }
    }

    @Test func theWholeEventFiveChairsAtATime() throws {
        try seatFiveBoards()
        try runBoard(finalYouth(1))
        try seat("104", finalYouth(4), chair: chairOfEither, member(1), member(2))
        try night.postponeBoard(scoutID: finalYouth(9))
        try night.resetBoard(scoutID: finalYouth(2))
        try night.startReview(scoutID: projectYouth(1))
        try night.resetBoard(scoutID: projectYouth(1))

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
        for youth in night.scouts where youth.status == .completed {
            let chair = night.adult(id: youth.boardChairID)
            #expect(chair != nil && youth.boardType.map { chair!.canChair($0) } == true, "\(youth.fullName) had a qualified chair")
        }

        // And it is all on disk: a fresh open of the folder sees the same night.
        let reopened = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
        #expect(reopened.scouts.filter { $0.status == .completed }.count == 13)
        #expect(reopened.adults.filter(\.isOnBoard).isEmpty)
        #expect(reopened.rooms.allSatisfy { $0.isFree })
    }

    // MARK: - What goes wrong on the night
    //
    // Carried over from sections 9-18 of the Java project's
    // test-board-event.sh. Where a Java case cannot arise here, the test
    // that stands in for it says why.

    @discardableResult
    private func lateYouth(_ last: String, _ first: String, unit: Int, _ boardType: String = "Final") throws -> String {
        try night.registerYouth([
            "Last": last, "First": first, "Email": "x\(unit)@example.org",
            "UnitType": "Troop", "Unit": "\(unit)", "BoardType": boardType,
        ])
        return "SCOUT:\(last):\(first):\(unit)"
    }

    private func result(_ scoutID: String) -> String? { night.scout(id: scoutID)?.result }

    /// What the Youth page does: edit fields of a youth and save it.
    private func editYouth(_ scoutID: String, _ change: (inout Scout) -> Void) throws {
        var record = try #require(night.scout(id: scoutID))
        change(&record)
        try night.updateYouth(record)
    }

    // Java section 9. Unknown ids and occupied rooms. (Missing parameters and
    // duplicated ids are the Java HTTP API's problem: here members are an
    // array, de-duplicated before they are counted -- see
    // compositionRulesHoldWithoutTheSeatBoardSheet.)
    @Test func requestsTheSeatBoardSheetWouldNeverMake() throws {
        refused("an unknown room") { try seat("999", finalYouth(1), chair: chairOfEither, member(1), member(2)) }
        refused("an unknown youth") { try seat("101", "SCOUT:Nobody:Here:0", chair: chairOfEither, member(1), member(2)) }
        refused("an unknown member") { try seat("101", finalYouth(1), chair: chairOfEither, member(1), "ADULT:Nobody:Here:0") }
        refused("an unknown youth cannot be started") { try night.startReview(scoutID: "SCOUT:Nobody:Here:0") }
        refused("an unknown youth cannot be completed") {
            try night.completeBoard(scoutID: "SCOUT:Nobody:Here:0", result: .approved, notes: "")
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
        try night.postponeBoard(scoutID: finalYouth(9))

        refused("a Completed youth cannot be seated again") { try seat("102", finalYouth(1), chair: finalChair2, member(3), member(4)) }
        refused("a Postponed youth cannot be seated") { try seat("102", finalYouth(9), chair: finalChair2, member(3), member(4)) }
        refused("a waiting youth cannot be started") { try night.startReview(scoutID: finalYouth(2)) }
        refused("a Completed youth cannot be started") { try night.startReview(scoutID: finalYouth(1)) }
        refused("a waiting youth cannot be completed") { try night.completeBoard(scoutID: finalYouth(2), result: .approved, notes: "") }
        refused("a Completed youth cannot be completed again") {
            try night.completeBoard(scoutID: finalYouth(1), result: .notApproved, notes: "")
        }
        refused("a Completed youth cannot be reset") { try night.resetBoard(scoutID: finalYouth(1)) }
        refused("a Postponed youth cannot be reset") { try night.resetBoard(scoutID: finalYouth(9)) }
        refused("a Completed youth cannot be postponed") { try night.postponeBoard(scoutID: finalYouth(1)) }
        #expect(result(finalYouth(1)) == "Approved", "the result survived all of that")

        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))
        try night.startReview(scoutID: finalYouth(2))
        do {
            try night.postponeBoard(scoutID: finalYouth(2))
            Issue.record("a review under way cannot be postponed")
        } catch let refusal as EventError {
            #expect(refusal.message.hasSuffix("is 'In review'."), "the alert says the badge's word, not the stored InProgress")
        }
        try night.completeBoard(scoutID: finalYouth(2), result: .adjourned, notes: "")
        #expect(result(finalYouth(2)) == "Adjourned")
        try seat("200A", projectYouth(1), chair: projectChair1, member(7))
        try night.startReview(scoutID: projectYouth(1))
        try night.completeBoard(scoutID: projectYouth(1), result: .notApproved, notes: "")
        #expect(result(projectYouth(1)) == "NotApproved")
        #expect(busyAdults == 0)
    }

    // Java section 11.
    @Test func signingInAgainMidBoardChangesNothing() throws {
        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))
        try night.startReview(scoutID: finalYouth(2))
        try registerAdult(8, unit: 2008, project: "Member", final: "Member")  // member(3)
        try registerAdult(2, unit: 2002, project: "Member", final: "Chair")   // finalChair2
        #expect(adultRoom(member(3)) == "102", "a member who signs in again stays in their room")
        #expect(adultRoom(finalChair2) == "102", "so does the chair")
        #expect(night.adult(id: finalChair2)?.canChair(.finalBoard) == true)

        try night.registerYouth([
            "Last": "Bram", "First": "Beauregard", "Email": "again@example.org",
            "UnitType": "Troop", "Unit": "1002", "BoardType": "Final",
        ])
        #expect(status(finalYouth(2)) == .inProgress, "a youth who signs in again is still under review")
        #expect(roomOf(finalYouth(2)) == "102")
        #expect(night.scouts.filter { $0.id == finalYouth(2) }.count == 1, "and is still one youth, not two")
        try night.completeBoard(scoutID: finalYouth(2), result: .approved, notes: "")
        #expect(adultRoom(member(3)) == "")
    }

    // Java section 12.
    @Test func aBoardMovesToAnotherRoom() throws {
        try seat("103", finalYouth(4), chair: finalChair3, member(5), member(6))
        try night.swapRooms("ROOM:103", "ROOM:106")
        #expect(roomOf(finalYouth(4)) == "106")
        #expect([finalChair3, member(5), member(6)].map(adultRoom) == ["106", "106", "106"])
        #expect(night.room(named: "103")?.isFree == true)

        try seat("103", finalYouth(5), chair: chairOfEither, member(1), member(2))
        try night.swapRooms("ROOM:103", "ROOM:106")
        #expect(roomOf(finalYouth(4)) == "103" && roomOf(finalYouth(5)) == "106", "each youth took the other's room")
        #expect(adultRoom(finalChair3) == "103" && adultRoom(chairOfEither) == "106", "each chair went with their own board")
        refused("swapping with a room that does not exist") { try night.swapRooms("ROOM:103", "ROOM:nope") }
        refused("swapping a room with itself") { try night.swapRooms("ROOM:103", "ROOM:103") }

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
        refused("a room with a board in it cannot be removed") { try night.removeRoom(id: "ROOM:104") }
        try runBoard(finalYouth(6))
        try night.removeRoom(id: "ROOM:104")
        #expect(night.room(named: "104") == nil)
    }

    @Test func anEmptyRoomIsRenamed() throws {
        let newID = try night.renameRoom(id: "ROOM:104", to: "  104 Annex ")
        #expect(newID == "ROOM:104 Annex", "the ID follows the name, trimmed")
        #expect(night.room(named: "104") == nil)
        #expect(night.room(id: newID)?.boardType == .finalBoard, "and keeps what it is used for")
        try seat("104 Annex", finalYouth(1), chair: chairOfEither, member(1), member(2))
        #expect(adultRoom(chairOfEither) == "104 Annex")
        try night.addRoom(named: "104", boardType: .finalBoard)  // the old name is free again

        let reopened = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
        #expect(reopened.room(id: newID)?.scoutName == "Alexander Aldridge", "the rename is on disk")
    }

    @Test func aBoardMovesWithItsRoomWhenTheRoomIsRenamed() throws {
        try seat("104", finalYouth(6), chair: chairOfEither, member(1), member(2))
        try night.startReview(scoutID: finalYouth(6))
        let clockBefore = night.scout(id: finalYouth(6))?["LastUpdateTime"]

        let newID = try night.renameRoom(id: "ROOM:104", to: "Library")
        #expect(roomOf(finalYouth(6)) == "Library", "the youth moves with the room")
        #expect([chairOfEither, member(1), member(2)].map(adultRoom) == ["Library", "Library", "Library"],
                "and so does every member")
        #expect(night.room(id: newID)?.scoutName == "Finnegan Fenwick", "the card still names the youth")
        #expect(status(finalYouth(6)) == .inProgress, "the review carries on")
        #expect(night.scout(id: finalYouth(6))?["LastUpdateTime"] == clockBefore, "and its timer was not restarted")
        refused("the renamed room is still occupied") { try seat("Library", finalYouth(7), chair: finalChair2, member(3), member(4)) }
        refused("its adults are still committed") { try seat("105", finalYouth(7), chair: chairOfEither, member(3), member(4)) }

        try night.completeBoard(scoutID: finalYouth(6), result: .approved, notes: "")
        #expect(busyAdults == 0, "completing releases every member, none stranded on the old name")
        #expect(night.room(id: newID)?.isFree == true)
    }

    @Test func aRoomCannotBeRenamedToSomethingItCannotBe() throws {
        refused("an empty name") { try night.renameRoom(id: "ROOM:104", to: "  ") }
        refused("a name with a comma") { try night.renameRoom(id: "ROOM:104", to: "104, east") }
        refused("a name another room has") { try night.renameRoom(id: "ROOM:104", to: "105") }
        refused("N/A, which marks adults who have gone home") { try night.renameRoom(id: "ROOM:104", to: disabledForTonightMarker) }
        refused("a room that does not exist") { try night.renameRoom(id: "ROOM:nope", to: "999") }
        refused("nor can a room be added as N/A") { try night.addRoom(named: disabledForTonightMarker, boardType: .finalBoard) }
        #expect(try night.renameRoom(id: "ROOM:104", to: "104") == "ROOM:104", "renaming to its own name changes nothing")
        #expect(night.rooms.count == 12)
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
        try night.registerAdult(form)
        let junior = "ADULT:Whitmore~ Jr.:Lysander:2031"
        #expect(night.adult(id: junior) != nil, "their id carries no comma")
        try seat("101", finalYouth(7), chair: chairOfEither, member(1), junior)
        #expect(adultRoom(junior) == "101")

        let reopened = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
        #expect(reopened.adult(id: junior)?.room == "101", "and are the same person after a restart")
        try reopened.registerAdult(form)
        #expect(reopened.adults.filter { $0.first == "Lysander" }.count == 1, "signing in again does not make a second one")
        try reopened.startReview(scoutID: finalYouth(7))
        try reopened.completeBoard(scoutID: finalYouth(7), result: .approved, notes: "")
        #expect(reopened.adult(id: junior)?.room == "")
    }

    // Java section 15 (two operators seating the same chair at once) has no
    // counterpart: EventNight is @MainActor, so every change runs one at a time.

    // Java section 16.
    @Test func theAppRestartsInTheMiddleOfTheEvent() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        try night.startReview(scoutID: finalYouth(1))
        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))

        let reopened = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
        #expect(reopened.scouts.count == night.scouts.count, "no youth lost or duplicated")
        #expect(reopened.adults.count == night.adults.count, "no adult lost or duplicated")
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
        try night.setBoardType(.finalBoard, forRoom: "ROOM:201A")
        refused("a Final board of 2 is still refused in a room switched to Final") {
            try seat("201A", finalYouth(1), chair: chairOfEither, member(1))
        }
        try seat("201A", finalYouth(1), chair: chairOfEither, member(1), member(2))

        try night.setBoardType(.projectReview, forRoom: "ROOM:106")
        refused("a Member still cannot chair a project review in a room switched to Project") {
            try seat("106", projectYouth(1), chair: member(3), member(4))
        }
        refused("nor can a Final-only chair") { try seat("106", projectYouth(1), chair: finalChair2, member(3)) }
        try seat("106", projectYouth(1), chair: projectChair1, member(3))

        try night.setBoardType(.projectReview, forRoom: "ROOM:102")
        try seat("102", finalYouth(2), chair: finalChair2, member(5), member(6))  // on purpose, as the sheet allows

        try night.startReview(scoutID: finalYouth(1))
        try night.setBoardType(.projectReview, forRoom: "ROOM:201A")
        try night.setBoardType(.finalBoard, forRoom: "ROOM:106")
        #expect(night.room(named: "201A")?.scoutName == "Alexander Aldridge", "switching a room keeps the board in it")
        #expect(adultRoom(chairOfEither) == "201A")
        #expect(status(finalYouth(1)) == .inProgress)
        #expect(night.scout(id: finalYouth(1))?.boardType == .finalBoard)

        try night.completeBoard(scoutID: finalYouth(1), result: .approved, notes: "")
        try runBoard(projectYouth(1))
        try runBoard(finalYouth(2))
        #expect([finalYouth(1), projectYouth(1), finalYouth(2)].map { night.scout(id: $0)?.boardChairID }
            == [chairOfEither, projectChair1, finalChair2], "every board kept the chair it was seated with")
        #expect(busyAdults == 0)
    }

    // Java section 18. Corrections made on the Youth page, whose Status and
    // Result menus offer BoardStatus.recordsChoices and BoardResult.allCases.
    @Test func aResultCorrectedOnTheYouthPage() throws {
        #expect(BoardStatus.recordsChoices.contains(.registered), "Registered is offered, to undo a result on the wrong youth")
        #expect(Set(BoardStatus.recordsChoices.map(\.label)).count == BoardStatus.recordsChoices.count,
                "no two choices read alike: legacy Verified, which also reads Waiting, is not offered")
        #expect(BoardResult.allCases.map(\.rawValue) == ["Approved", "Adjourned", "NotApproved"],
                "results are exactly the board's three decisions; Postponed is a status, not a result")

        // The wrong result clicked.
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        try runBoard(finalYouth(1))
        try editYouth(finalYouth(1)) { $0.result = "NotApproved" }
        #expect(result(finalYouth(1)) == "NotApproved")
        #expect(status(finalYouth(1)) == .completed)
        #expect(night.scout(id: finalYouth(1))?.boardChairID == chairOfEither)
        #expect(busyAdults == 0)

        // The right result on the wrong youth.
        let right = try lateYouth("Esterhazy", "Quentin", unit: 3302)
        let wrong = try lateYouth("Esterbrook", "Quentin", unit: 3303)
        try seat("102", wrong, chair: finalChair2, member(3), member(4))
        try runBoard(wrong)
        let board = try #require(night.scout(id: wrong))
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
        #expect(night.scout(id: right)?.boardChair == board.boardChair)
        #expect(status(wrong) == .registered && result(wrong) == "")
        refused("the reviewed youth cannot be seated again") { try seat("103", right, chair: finalChair3, member(5), member(6)) }
        try seat("103", wrong, chair: finalChair3, member(5), member(6))
        try night.startReview(scoutID: wrong)
        try night.completeBoard(scoutID: wrong, result: .notApproved, notes: "")
        #expect(result(wrong) == "NotApproved" && night.scout(id: wrong)?.boardChairID == finalChair3)
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
        refused("a youth sent away cannot be seated again that night") { try seat("104", sent, chair: chairOfEither, member(1), member(2)) }
        #expect(busyAdults == 0)
    }

    // Java section 19. What an adult says at sign-in.
    @Test func woodBadgeNoThanksAndTheYouthAnAdultCameToSupport() throws {
        let rsvp = try lateYouth("Galloway", "Tobias", unit: 3401)
        var form = [
            "Last": "Hargrove", "First": "Ines", "Email": "a41@example.org", "UnitType": "Troop", "Unit": "3401",
            "ProjectReview": "Member", "FinalBoard": "Member",
            "WoodBadge": "Y", "Supporting": "\(rsvp)|SCOUT:Nobody:Here:0",
        ]
        try night.registerAdult(form)
        let leader = "ADULT:Hargrove:Ines:3401"
        #expect(night.adult(id: leader)?.woodBadge == "Y", "Wood Badge is recorded")
        #expect(night.adult(id: leader)?.supporting == "\(rsvp)|SCOUT:Nobody:Here:0", "and whom they came to support")
        let history = try #require(night.adultHistory.first { $0.id == leader })
        #expect(history.woodBadge.isEmpty && history.supporting.isEmpty, "neither is kept for next month")

        form["WoodBadge"] = "yes"
        form["Supporting"] = ""
        try night.registerAdult(form)
        #expect(night.adult(id: leader)?.supporting == "", "signing in again says what is true now")
        #expect(night.adult(id: leader)?.woodBadge == "", "and Wood Badge is Y or nothing")

        // "No thanks" is stored as Unavailable; Seat Board refuses them there.
        try night.registerAdult([
            "Last": "Ibarra", "First": "Juno", "Email": "a42@example.org", "UnitType": "Troop", "Unit": "3402",
            "ProjectReview": "Unavailable", "FinalBoard": "Member",
        ])
        let noProject = "ADULT:Ibarra:Juno:3402"
        #expect(night.adult(id: noProject)?.projectReviewRoleText == "Unavailable")
        let project = try lateYouth("Jaramillo", "Kai", unit: 3403, "Project")
        refused("they are not seated on a proposal review") { try seat("200A", project, chair: projectChair1, noProject) }
        #expect(busyAdults == 0)
        try seat("101", rsvp, chair: chairOfEither, member(1), noProject)  // a Final board is fine
        try night.resetBoard(scoutID: rsvp)

        // The sign-in list: RSVPs not yet here, and this event's youth who are
        // not done yet.
        try CSVFile.write([Scout(fields: [
            "Type": "SCOUT", "ID": "SCOUT:Rsvp:Only:3999", "Last": "Rsvp", "First": "Only",
            "UnitType": "Troop", "Unit": "3999", "BoardType": "Final",
        ])], to: scratch.dataFolder.scheduledYouthURL(night: "2026-09-22"))
        try night.postponeBoard(scoutID: finalYouth(9))
        let reopened = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
        let choices = reopened.scoutChoices().map(\.id)
        #expect(choices.contains("SCOUT:Rsvp:Only:3999"), "an RSVP not yet signed in can be chosen")
        #expect(choices.contains(rsvp), "so can someone signed in tonight")
        #expect(!choices.contains(finalYouth(9)), "but not someone done for the event")
    }

    // Java section 19, linking after both have signed in.
    @Test func anOperatorLinksAnAdultToAYouthAfterBothSignedIn() throws {
        try night.setSupporting(true, adultID: member(1), scoutID: finalYouth(1))
        #expect(night.adult(id: member(1))?.supporting == finalYouth(1))
        try night.setSupporting(true, adultID: member(1), scoutID: finalYouth(1))
        #expect(night.adult(id: member(1))?.supporting == finalYouth(1), "pressing it twice links once")

        try seat("101", finalYouth(1), chair: chairOfEither, member(2), member(3))
        try runBoard(finalYouth(1))
        #expect(night.adult(id: member(1))?.supporting == finalYouth(1), "the link survives the youth's board")

        try night.setSupporting(false, adultID: member(1), scoutID: finalYouth(1))
        #expect(night.adult(id: member(1))?.supporting == "", "and can be undone")

        refused("an unknown adult") { try night.setSupporting(true, adultID: "ADULT:Nobody:Here:0", scoutID: finalYouth(2)) }
        refused("an unknown youth") { try night.setSupporting(true, adultID: member(1), scoutID: "SCOUT:Nobody:Here:0") }
        try night.setSupporting(false, adultID: member(1), scoutID: "SCOUT:Nobody:Here:0")  // clearing a stale link is fine
    }

    @Test func startReviewNamesWhoCameToSupportTheYouthAndWhereTheyAre() throws {
        try night.registerAdult([
            "Last": "Scoutmaster", "First": "Sam", "Email": "sm@example.org", "UnitType": "Troop", "Unit": "1001",
            "ProjectReview": "Member", "FinalBoard": "Member", "Supporting": finalYouth(1),
        ])
        let scoutmaster = "ADULT:Scoutmaster:Sam:1001"
        try seat("102", finalYouth(2), chair: finalChair2, member(3), scoutmaster)  // sitting on another board
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        let youth = try #require(night.scout(id: finalYouth(1)))
        let first = try #require(AdultLocator.locate(for: youth, among: night.adults).first)
        #expect(first.adult.id == scoutmaster && first.relation == .supporting)
        #expect(first.whereabouts == "Room 102", "so someone can fetch them from their board")
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
    // from the View pages and the board results report, checked below. The
    // Youth and Pre-Registered pages show no phone number and do not search
    // one, so neither has a filter that could say whose number it is.
    @Test func aYouthsPhoneNumberIsNotKeptButOneOnFileStays() throws {
        // A pre-registration given a birthdate and a phone number by hand, as
        // a file from before D-7 and D-8 would have them.
        try night.mergeSignUps([
            SignUpEntry(startDate: "2026-09-22 19:00", firstName: "lena", lastName: "lookup", item: "Eagle Board of Review",
                        email: "Lena.Lookup@Example.org", customAnswers: ["Troop 4401", "555-0100", ""]),
        ], month: "2026-09")
        var lena = try #require(night.scheduledYouth(matchingEmail: "  lena.lookup@EXAMPLE.org "))
        #expect(lena.phone == "", "SignUpGenius puts no phone number on a youth")
        lena.dateOfBirth = "2010-05-06"
        lena.phone = "555-0100"
        try night.updateYouth(lena, scheduled: true)
        let scheduledFile = try scratch.text("2026-09-22/scouts_scheduled.csv")
        #expect(scheduledFile.contains("555-0100") && scheduledFile.contains("2010-05-06"), "both stay on file")
        let scheduledList = CSVFile.render(night.scheduledScouts.map(\.forExport))
        #expect(!scheduledList.contains("555-0100") && !scheduledList.contains("2010-05-06"),
                "but the pre-registrations exported from the Pre-Registered page leave them out")

        // A new sign-in from an old cached page.
        var form = [
            "Last": "Oldpage", "First": "Olive", "Email": "op@example.org", "Phone": "555-0101",
            "UnitType": "Troop", "Unit": "4402", "BoardType": "Final", "DOB": "2011-02-03",
        ]
        try night.registerYouth(form)
        let olive = "SCOUT:Oldpage:Olive:4402"
        func onFile() throws -> String {
            let youth = try #require(CSVFile.read(Scout.self, from: scratch.dataFolder.youthURL(night: "2026-09-22"))
                .first(where: { $0.id == olive }))
            return "\(youth.dateOfBirth)|\(youth.phone)"
        }
        #expect(try onFile() == "|", "neither a birthdate nor a phone number from an old cached page is kept")

        try editYouth(olive) {
            $0.dateOfBirth = "2011-02-03"
            $0.phone = "555-0101"
        }
        #expect(try onFile() == "2011-02-03|555-0101", "one already on file stays on file")
        let report = Reports.csv(night.scouts, columns: Reports.boardResultColumns)
        #expect(!report.contains("2011-02-03") && !report.contains("555-0101"), "but the board results report never shows it")
        let youthList = CSVFile.render(night.scouts.map(\.forExport))
        #expect(!youthList.contains("2011-02-03") && !youthList.contains("555-0101"), "nor a list exported from the Youth page")
        #expect(CSVFile.parse(Scout.self, text: youthList).first(where: { $0.id == olive })?.first == "Olive",
                "which keeps the columns, so they still line up")

        form["Phone"] = "555-0199"
        form["DOB"] = "2012-12-12"
        try night.registerYouth(form)
        #expect(try onFile() == "2011-02-03|555-0101", "and signing in again neither changes nor blanks it")

        // An adult's number is kept, tonight and in the history the adult
        // lookup reads.
        try night.registerAdult([
            "Last": "Phoneon", "First": "Adele", "Email": "adele@example.org", "Phone": "555-0102",
            "UnitType": "Troop", "Unit": "4403", "ProjectReview": "Member", "FinalBoard": "Member",
        ])
        #expect(night.adult(id: "ADULT:Phoneon:Adele:4403")?.phone == "555-0102")
        #expect(night.knownAdult(matchingEmail: "adele@example.org")?.phone == "555-0102")
    }

    // MARK: - Undo

    /// Undo of each step is restoreBoard with the record from before it.
    @Test func eachStepIsUndoneAndRedone() throws {
        let waiting = try #require(night.scout(id: finalYouth(1)))
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        let seated = try #require(night.scout(id: finalYouth(1)))

        try night.restoreBoard(waiting)
        #expect(status(finalYouth(1)) == .registered)
        #expect(roomOf(finalYouth(1)) == "")
        #expect(adultRoom(chairOfEither) == "")
        #expect(night.room(named: "101")?.isFree == true)

        try night.restoreBoard(seated)
        #expect(status(finalYouth(1)) == .seated)
        #expect(adultRoom(member(2)) == "101")
        #expect(night.room(named: "101")?.scoutName == seated.fullName)

        try night.startReview(scoutID: finalYouth(1))
        let inReview = try #require(night.scout(id: finalYouth(1)))
        try night.restoreBoard(seated)
        #expect(status(finalYouth(1)) == .seated)
        #expect(night.scout(id: finalYouth(1))?.lastUpdateTime == seated.lastUpdateTime, "the convening timer resumes")
        try night.restoreBoard(inReview)

        try night.completeBoard(scoutID: finalYouth(1), result: .adjourned, notes: "Come back next month")
        #expect(adultRoom(chairOfEither) == "")
        try night.restoreBoard(inReview)
        #expect(status(finalYouth(1)) == .inProgress)
        #expect(night.scout(id: finalYouth(1))?.result == "")
        #expect(night.scout(id: finalYouth(1))?.notes == "")
        #expect(adultRoom(chairOfEither) == "101", "the members are back on the board")
        #expect(night.room(named: "101")?.isFree == false)

        try night.resetBoard(scoutID: finalYouth(1))
        try night.restoreBoard(inReview)
        #expect(status(finalYouth(1)) == .inProgress)
        #expect(adultRoom(member(1)) == "101")

        let other = try #require(night.scout(id: finalYouth(2)))
        try night.postponeBoard(scoutID: finalYouth(2))
        try night.restoreBoard(other)
        #expect(status(finalYouth(2)) == .registered)
    }

    /// Undo cannot put anyone on two boards: once the room or a member has
    /// been given to another board, the old board stays as it is.
    @Test func undoIsRefusedOnceTheEventHasMovedOn() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        let seated = try #require(night.scout(id: finalYouth(1)))
        try night.resetBoard(scoutID: finalYouth(1))

        try seat("101", finalYouth(2), chair: finalChair2, member(3), member(4))
        refused("room 101 has another board now") { try night.restoreBoard(seated) }
        #expect(status(finalYouth(1)) == .registered)
        #expect(night.room(named: "101")?.scoutName == night.scout(id: finalYouth(2))?.fullName)

        try night.resetBoard(scoutID: finalYouth(2))
        try seat("102", finalYouth(3), chair: finalChair3, member(1), member(5))
        refused("a member is on another board now") { try night.restoreBoard(seated) }
        #expect(adultRoom(member(1)) == "102")

        try night.resetBoard(scoutID: finalYouth(3))
        try night.setAvailable(false, adultID: member(2))
        refused("a member has gone home") { try night.restoreBoard(seated) }

        try night.setAvailable(true, adultID: member(2))
        try night.restoreBoard(seated)
        #expect(status(finalYouth(1)) == .seated)
    }

    private func seatFiveBoards() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))
        try seat("103", finalYouth(3), chair: finalChair3, member(5), member(6))
        try seat("200A", projectYouth(1), chair: projectChair1, member(7))
        try seat("200B", projectYouth(2), chair: projectChair2, member(8))
    }
}
