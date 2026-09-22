import EagleBoardsCore
import Foundation
import Testing

@MainActor
@Suite("Signing in")
struct SignInTests {
    let scratch: ScratchFolder
    let clock = TestClock()
    let night: EventNight

    init() throws {
        scratch = try ScratchFolder()
        let clock = self.clock
        night = try EventNight(folder: scratch.dataFolder, night: "2026-09-22", clock: { clock.now })
    }

    private func youthForm(_ first: String, _ last: String, email: String, unit: String = "1776", boardType: String = "Final") -> [String: String] {
        ["First": first, "Last": last, "Email": email, "UnitType": "Troop", "Unit": unit, "BoardType": boardType, "Phone": "555", "DOB": "1/1/2010"]
    }

    @Test func walkInsAndPreRegisteredAreNumberedSeparately() throws {
        try night.mergeSignUps([
            SignUpEntry(startDate: "2026-09-22 19:00", firstName: "pat", lastName: "prereg", item: "Eagle Board of Review",
                        email: "Pat@Example.org", customAnswers: ["Troop 1776", "7705550100", "lee leader"]),
        ], month: "2026-09")

        let walkIn = try night.registerYouth(youthForm("Wally", "Walkin", email: "wally@example.org"))
        let preRegistered = try night.registerYouth(youthForm("Pat", "Prereg", email: "pat@example.org"))
        let secondWalkIn = try night.registerYouth(youthForm("Wanda", "Walkin", email: "NONE"))

        #expect(walkIn.regNum == "W1")
        #expect(preRegistered.regNum == "P1", "matched by email, ignoring case")
        #expect(secondWalkIn.regNum == "W2")
        #expect(night.scouts.allSatisfy { $0.status == .registered })
    }

    @Test func signingInAgainChangesOnlyTheSignInFields() throws {
        let first = try night.registerYouth(youthForm("Jan", "Doe", email: "jan@example.org"))
        try night.addRoom(named: "101", boardType: .finalBoard)
        var seatedCopy = try #require(night.scout(id: first.id))
        seatedCopy.status = .seated
        seatedCopy.room = "101"
        try night.updateYouth(seatedCopy)

        var again = youthForm("Jan", "Doe", email: "jan@example.org", boardType: "Project")
        again["Phone"] = "770-555-0199"
        again["Status"] = "Completed"
        again["Result"] = "Approved"
        let updated = try night.registerYouth(again)

        #expect(night.scouts.count == 1)
        #expect(updated.phone == "770-555-0199")
        #expect(updated.status == .seated, "status is not a sign-in field")
        #expect(updated.room == "101")
        #expect(updated.result == "")
        #expect(updated.boardType == .finalBoard, "board type is set at first sign-in only")
        #expect(updated.regNum == first.regNum, "keeps its place in line")
    }

    @Test func aNameIsRequired() {
        #expect(throws: EventError.self) { try night.registerYouth(["Email": "x@example.org", "BoardType": "Final"]) }
        #expect(throws: EventError.self) { try night.registerAdult(["First": "Only"]) }
        #expect(night.scouts.isEmpty && night.adults.isEmpty)
    }

    @Test func aNewAdultIsAddedToTheHistoryWithTonightsDate() throws {
        let adult = try night.registerAdult([
            "First": "Morgan", "Last": "Member", "Email": "morgan@example.org", "UnitType": "Crew", "Unit": "55",
            "FinalBoard": "Chair", "ProjectReview": "Member",
        ])
        #expect(adult.id == "ADULT:Member:Morgan:55")
        #expect(adult.flags == "W", "new to the history")
        #expect(night.adultHistory.count == 1)
        #expect(night.adultHistory[0].boardHistory == "(\(Timestamp.dayStamp(for: clock.now)))")
        #expect(night.adultHistory[0].canChair(.finalBoard))
    }

    @Test func aReturningAdultIsRecognizedAndTheirHistoryUpdated() throws {
        try scratch.write(
            "Type,ID,Last,First,Email,Phone,UnitType,Unit,UnitName,ProjectReview,FinalBoard,RegTime,Room,Flags,Sel,BoardHistory\n"
                + "ADULT,ADULT:Member:Morgan:55,Member,Morgan,morgan@example.org,111,Crew,55,Crew55,Member,Member,,,,,(2026-08-25)\n",
            to: "Master_AdultHistory.csv"
        )
        let reopened = try EventNight(folder: scratch.dataFolder, night: "2026-09-22", clock: { [clock] in clock.now })
        let known = try #require(reopened.knownAdult(matchingEmail: " MORGAN@example.org "))
        #expect(known.phone == "111")

        let adult = try reopened.registerAdult([
            "ID": known.id, "First": "Morgan", "Last": "Member", "Email": "morgan@example.org", "UnitType": "Crew", "Unit": "55",
            "Phone": "222", "FinalBoard": "Member", "ProjectReview": "Chair",
        ])
        #expect(adult.flags == "P", "already in the history")
        #expect(reopened.adultHistory.count == 1)
        #expect(reopened.adultHistory[0].phone == "222")
        #expect(reopened.adultHistory[0].canChair(.projectReview))
        #expect(reopened.adultHistory[0].boardHistory == "(2026-08-25)(\(Timestamp.dayStamp(for: clock.now)))")

        // Signing in twice in a night records the night once, and a form that
        // leaves the roles out does not demote a chair.
        let again = try reopened.registerAdult(["First": "Morgan", "Last": "Member", "UnitType": "Crew", "Unit": "55"])
        #expect(reopened.adultHistory[0].boardHistory.components(separatedBy: "(").count == 3)
        #expect(again.canChair(.projectReview))
        #expect(reopened.adultHistory[0].canChair(.projectReview))
    }

    @Test func aKnownChairWhoLeavesTheRolesBlankIsStillAChair() throws {
        try scratch.write(
            "Type,ID,Last,First,Email,Phone,UnitType,Unit,UnitName,ProjectReview,FinalBoard,RegTime,Room,Flags,Sel,BoardHistory\n"
                + "ADULT,ADULT:Chair:Chris:7,Chair,Chris,chris@example.org,,Troop,7,Troop7,Member,Chair,,,,,(2026-08-25)\n",
            to: "Master_AdultHistory.csv"
        )
        let reopened = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
        let chris = try reopened.registerAdult(["First": "Chris", "Last": "Chair", "UnitType": "Troop", "Unit": "7", "FinalBoard": "Nonsense"])
        #expect(chris.canChair(.finalBoard), "taken from the history")
        #expect(chris.role(for: .projectReview) == .member)
        let newcomer = try reopened.registerAdult(["First": "New", "Last": "Person", "UnitType": "Troop", "Unit": "8"])
        #expect(newcomer.role(for: .finalBoard) == .member && newcomer.role(for: .projectReview) == .member)
    }

    @Test func signingInAgainDoesNotTakeAnAdultOffTheirBoard() throws {
        var adult = try night.registerAdult(["First": "Morgan", "Last": "Member", "UnitType": "Troop", "Unit": "9"])
        adult.room = "101"
        try night.updateAdult(adult)
        let again = try night.registerAdult(["First": "Morgan", "Last": "Member", "UnitType": "Troop", "Unit": "9", "Phone": "333"])
        #expect(again.room == "101")
        #expect(again.phone == "333")
    }

    @Test func unitlessAdultsHaveNoUnitNumber() throws {
        let adult = try night.registerAdult(["First": "Dana", "Last": "District", "UnitType": "District", "Unit": "12"])
        #expect(adult.unit == "")
        #expect(adult.unitName == "District")
        #expect(adult.unitLabel == "District")
    }

    @Test func blankOrNoneEmailsNeverMatch() throws {
        try night.registerAdult(["First": "No", "Last": "Email", "Email": "NONE", "UnitType": "Troop", "Unit": "1"])
        #expect(night.knownAdult(matchingEmail: "none") == nil)
        #expect(night.knownAdult(matchingEmail: "") == nil)
    }

    @Test func minutesRunFromTheLastChange() throws {
        let youth = try night.registerYouth(youthForm("Jan", "Doe", email: "jan@example.org"))
        clock.advance(minutes: 12)
        #expect(night.scout(id: youth.id)?.minutesSinceLastUpdate(now: night.now) == 12)
        try night.postponeBoard(scoutID: youth.id)
        #expect(night.scout(id: youth.id)?.minutesSinceLastUpdate(now: night.now) == 0, "a status change restarts the clock")
    }
}

@MainActor
@Suite("Rooms")
struct RoomTests {
    let scratch: ScratchFolder
    let night: EventNight

    init() throws {
        scratch = try ScratchFolder()
        night = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
    }

    @Test func roomsAreUniqueAndNamed() throws {
        try night.addRoom(named: " 101 ", boardType: .finalBoard)
        #expect(night.room(id: "ROOM:101")?.name == "101")
        #expect(throws: EventError.self) { try night.addRoom(named: "101", boardType: .projectReview) }
        #expect(throws: EventError.self) { try night.addRoom(named: "  ", boardType: .projectReview) }
        #expect(throws: EventError.self) { try night.addRoom(named: "1,2", boardType: .projectReview) }

        #expect(throws: EventError.self) { try night.swapRooms("ROOM:101", "ROOM:101") }
    }

    @Test func swappingMovesTheYouthTheMembersAndTheCard() throws {
        try night.addRoom(named: "101", boardType: .finalBoard)
        try night.addRoom(named: "102", boardType: .finalBoard)
        for (first, role) in [("Chris", "Chair"), ("Morgan", "Member"), ("Taylor", "Member")] {
            try night.registerAdult(["First": first, "Last": "Adult", "UnitType": "Troop", "Unit": first.count.description + "0", "FinalBoard": role])
        }
        let youth = try night.registerYouth(["First": "Jan", "Last": "Doe", "UnitType": "Troop", "Unit": "1776", "BoardType": "Final"])
        let adultIDs = night.adults.map(\.id)
        try night.seatBoard(roomID: "ROOM:101", scoutID: youth.id, chairID: adultIDs[0], memberIDs: adultIDs)

        try night.swapRooms("ROOM:101", "ROOM:102")
        #expect(night.scout(id: youth.id)?.room == "102")
        #expect(night.adults.allSatisfy { $0.room == "102" })
        #expect(night.room(named: "102")?.scoutName == "Jan Doe")
        #expect(night.room(named: "101")?.isFree == true)
        #expect(throws: EventError.self) { try night.removeRoom(id: "ROOM:102") }
        try night.removeRoom(id: "ROOM:101")
        #expect(night.rooms.map(\.name) == ["102"])
    }

    @Test func roomsCopyFromAnEarlierNightEmpty() throws {
        try scratch.write(
            "Type,ID,Room,BoardType,Scout,Leaders,RegTime\nROOM,ROOM:101,101,Final,Old Youth,Old Adults,\nROOM,ROOM:200A,200A,Project,,,\n",
            to: "2026-08-25/rooms.csv"
        )
        try night.addRoom(named: "101", boardType: .finalBoard)
        #expect(try night.copyRooms(fromNight: "2026-08-25") == 1)
        #expect(night.rooms.map(\.name) == ["101", "200A"])
        #expect(night.rooms.allSatisfy { $0.isFree })
        #expect(scratch.dataFolder.nights() == ["2026-09-22", "2026-08-25"])
    }
}

@MainActor
@Suite("SignUpGenius import")
struct SignUpImportTests {
    let scratch: ScratchFolder
    let night: EventNight

    init() throws {
        scratch = try ScratchFolder()
        night = try EventNight(folder: scratch.dataFolder, night: "2026-09-22")
    }

    @Test func entriesBecomeHistoryAndPreRegistrations() throws {
        try night.registerAdult(["First": "Known", "Last": "Adult", "Email": "known@example.org", "UnitType": "Troop", "Unit": "1", "Phone": "old"])
        let summary = try night.mergeSignUps([
            SignUpEntry(startDate: "2026-09-22 19:00", firstName: "known", lastName: "adult", item: "Adult Board Member",
                        email: "KNOWN@example.org", customAnswers: ["Troop 1", "(770) 555-0100"]),
            SignUpEntry(startDate: "2026-09-22 19:00", firstName: "new", lastName: "van dyke", item: "Adult Board Member",
                        email: "new@example.org", customAnswers: ["Crew 55", "770.555.0101"]),
            SignUpEntry(startDate: "2026-09-22 19:00", firstName: "jan", lastName: "doe", item: "Eagle Board of Review",
                        email: "jan@example.org", customAnswers: ["T1776", "7705550102", "lee   leader"]),
            SignUpEntry(startDate: "2026-09-22 19:00", firstName: "sam", lastName: "smith", item: "Project Proposal Review",
                        email: "sam@example.org", customAnswers: ["Post 9", "", ""]),
            SignUpEntry(startDate: "2026-10-27 19:00", firstName: "next", lastName: "month", item: "Eagle Board of Review",
                        email: "later@example.org", customAnswers: []),
        ], month: "2026-09")

        #expect(summary == .init(addedAdults: 1, updatedAdults: 1, addedYouth: 2, outsideThisMonth: 1))
        #expect(night.knownAdult(matchingEmail: "known@example.org")?.phone == "770-555-0100")

        let added = try #require(night.knownAdult(matchingEmail: "new@example.org"))
        #expect(added.fullName == "New Van dyke")
        #expect(added.unitName == "Crew55")
        #expect(added.phone == "770-555-0101")
        #expect(added.role(for: .finalBoard) == .member && added.role(for: .projectReview) == .member)

        let jan = try #require(night.scheduledYouth(matchingEmail: "jan@example.org"))
        #expect(jan.id == "SCOUT:Doe:Jan:1776")
        #expect(jan.boardType == .finalBoard)
        #expect(jan.leader == "Lee Leader")
        #expect(night.scheduledYouth(matchingEmail: "sam@example.org")?.boardType == .projectReview)
        #expect(night.scheduledYouth(matchingEmail: "sam@example.org")?.unitName == "Post9")

        // Importing the same sign-up again adds nobody.
        let again = try night.mergeSignUps([
            SignUpEntry(startDate: "2026-09-22", firstName: "jan", lastName: "doe", item: "Eagle Board of Review",
                        email: "jan@example.org", customAnswers: []),
        ], month: "2026-09")
        #expect(again.alreadyScheduledYouth == 1)
        #expect(night.scheduledScouts.count == 2)
    }

    @Test(arguments: [
        ("(770) 555-0100", "770-555-0100"),
        ("770.555.0100", "770-555-0100"),
        ("555-0100", "555-0100"),
        ("1 (770) 555-0100", "770-555-0100"),
        ("ask my mom", "ask my mom"),
        ("", ""),
    ])
    func phonesAreFormattedFromTheirDigits(raw: String, formatted: String) {
        #expect(NameCleanup.phone(raw) == formatted)
    }

    @Test(arguments: [
        ("Troop 1776", UnitType.troop, "1776"),
        ("T1776", .troop, "1776"),
        ("crew 12", .crew, "12"),
        ("Post 9", .post, "9"),
        ("P42", .pack, "42"),
        ("Ship 3", .ship, "3"),
        ("1776", .troop, "1776"),
    ])
    func unitsAreRead(raw: String, type: UnitType, number: String) {
        let unit = NameCleanup.unit(from: raw)
        #expect(unit.type == type)
        #expect(unit.number == number)
    }

    @Test func slotNamesDecideTheBoardType() {
        #expect(NameCleanup.boardType(fromSlot: "Project Proposal Review") == .projectReview)
        #expect(NameCleanup.boardType(fromSlot: "Eagle Board of Review") == .finalBoard)
        #expect(NameCleanup.boardType(fromSlot: "Snacks") == nil)
    }
}
