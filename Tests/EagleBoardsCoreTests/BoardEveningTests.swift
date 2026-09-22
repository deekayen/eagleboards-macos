import EagleBoardsCore
import Foundation
import Testing

/// A whole board evening at the district's real shape, carried over from the
/// Java project's scripts/test-board-evening.sh:
///
///   14 youth (9 Final, 5 Project)     12 rooms (7 Final, 5 Project)
///   30 adults, of whom only FIVE may chair anything:
///       3 can chair a Final board, 3 a Project review, one of them both.
///
/// So the evening is capped at five concurrent boards no matter how many rooms
/// are free -- the constraint the scheduler actually has to survive. The rule
/// tests pin down the rules as pure functions; this pins down what the event
/// night does with them: boards convening and starting, adults committed to
/// one room and released when the review finishes, boards postponed and reset,
/// and the rules holding even for requests that skip the Seat Board sheet.
///
/// Add a case here when you change how a board is seated, run or torn down.
@MainActor
@Suite("A board evening")
struct BoardEveningTests {
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
    // committing them to a Final board is what drops the evening to two Project chairs.
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

    // MARK: - Helpers that read the evening back

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

    // MARK: - The evening

    @Test func theEveningAsSeeded() {
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

    @Test func fiveChairsCapTheEveningAtFiveConcurrentBoards() throws {
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

    @Test func theWholeEveningFiveChairsAtATime() throws {
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
        // failure that outlives the evening.
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

    private func seatFiveBoards() throws {
        try seat("101", finalYouth(1), chair: chairOfEither, member(1), member(2))
        try seat("102", finalYouth(2), chair: finalChair2, member(3), member(4))
        try seat("103", finalYouth(3), chair: finalChair3, member(5), member(6))
        try seat("200A", projectYouth(1), chair: projectChair1, member(7))
        try seat("200B", projectYouth(2), chair: projectChair2, member(8))
    }
}
