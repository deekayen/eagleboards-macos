import EagleBoardsCore
import Foundation
import Testing

@MainActor
@Suite("Signing in")
struct SignInTests {
    let scratch: ScratchFolder
    let clock = TestClock()
    let event: BoardEvent

    init() throws {
        scratch = try ScratchFolder()
        let clock = self.clock
        event = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22", clock: { clock.now })
    }

    /// What an older cached sign-in page sends: a phone number and birthdate
    /// too, neither of which is kept (SPEC.md D-7, D-8).
    private func youthForm(_ first: String, _ last: String, email: String, unit: String = "1776", boardType: String = "Final") -> [String: String] {
        ["First": first, "Last": last, "Email": email, "UnitType": "Troop", "Unit": unit, "BoardType": boardType, "Phone": "770-555-0100", "DOB": "1/1/2010"]
    }

    @Test func walkInsAndPreRegisteredAreNumberedSeparately() throws {
        try event.mergeSignUps([
            SignUpEntry(startDate: "2026-09-22 19:00", firstName: "pat", lastName: "prereg", item: "Eagle Board of Review",
                        email: "Pat@Example.org", customAnswers: ["Troop 1776", "7705550100", "lee leader"]),
        ], month: "2026-09")

        let walkIn = try event.registerYouth(youthForm("Wally", "Walkin", email: "wally@example.org"))
        let preRegistered = try event.registerYouth(youthForm("Pat", "Prereg", email: "pat@example.org"))
        let secondWalkIn = try event.registerYouth(youthForm("Wanda", "Walkin", email: "NONE"))

        #expect(walkIn.regNum == "W1")
        #expect(preRegistered.regNum == "P1", "matched by email, ignoring case")
        #expect(secondWalkIn.regNum == "W2")
        #expect(event.scouts.allSatisfy { $0.status == .registered })
    }

    @Test func signingInAgainChangesOnlyTheSignInFields() throws {
        let first = try event.registerYouth(youthForm("Jan", "Doe", email: "jan@example.org"))
        #expect(first.phone == "" && first.dateOfBirth == "", "a new youth's are empty (D-7, D-8)")
        try event.addRoom(named: "101", boardType: .finalBoard)
        let board = try ["Chair", "Member", "Other"].enumerated().map { index, last in
            try event.registerAdult(["First": "Pat", "Last": last, "UnitType": "Troop", "Unit": "\(index + 7)",
                                     "FinalBoard": index == 0 ? "Chair" : "Member"])
        }
        try event.seatBoard(roomID: "ROOM:101", scoutID: first.id, chairID: board[0].id, memberIDs: board.map(\.id))
        var seatedCopy = try #require(event.scout(id: first.id))
        // A number on file from before D-8.
        seatedCopy.phone = "770-555-0101"
        try event.updateYouth(seatedCopy)

        var again = youthForm("Jan", "Doe", email: "jan@example.org", boardType: "Project")
        again["Leader"] = "Lee Leader"
        again["Phone"] = "770-555-0199"
        again["Status"] = "Completed"
        again["Result"] = "Approved"
        let updated = try event.registerYouth(again)

        #expect(event.scouts.count == 1)
        #expect(updated.leader == "Lee Leader")
        #expect(updated.phone == "770-555-0101", "a phone number on file is left alone (D-8)")
        let file = try scratch.text("2026-09-22/scouts.csv")
        #expect(file.contains("770-555-0101") && !file.contains("770-555-0199"), "and carried through the rewrite")
        #expect(updated.status == .seated, "status is not a sign-in field")
        #expect(updated.room == "101")
        #expect(updated.result == "")
        #expect(updated.boardType == .finalBoard, "board type is set at first sign-in only")
        #expect(updated.regNum == first.regNum, "keeps its place in line")
    }

    @Test func aNameIsRequired() {
        #expect(throws: EventError.self) { try event.registerYouth(["Email": "x@example.org", "BoardType": "Final"]) }
        #expect(throws: EventError.self) { try event.registerAdult(["First": "Only"]) }
        #expect(event.scouts.isEmpty && event.adults.isEmpty)
    }

    @Test func aNewAdultIsAddedToTheHistoryWithTheEventsDate() throws {
        let adult = try event.registerAdult([
            "First": "Morgan", "Last": "Member", "Email": "morgan@example.org", "UnitType": "Crew", "Unit": "55",
            "FinalBoard": "Chair", "ProjectReview": "Member",
        ])
        #expect(adult.id == "ADULT:Member:Morgan:55")
        #expect(adult.flags == "W", "new to the history")
        #expect(event.adultHistory.count == 1)
        #expect(event.adultHistory[0].boardHistory == "(\(Timestamp.dayStamp(for: clock.now)))")
        #expect(event.adultHistory[0].canChair(.finalBoard))
    }

    @Test func aReturningAdultIsRecognizedAndTheirHistoryUpdated() throws {
        try scratch.write(
            "Type,ID,Last,First,Email,Phone,UnitType,Unit,UnitName,ProjectReview,FinalBoard,RegTime,Room,Flags,Sel,BoardHistory\n"
                + "ADULT,ADULT:Member:Morgan:55,Member,Morgan,morgan@example.org,111,Crew,55,Crew55,Member,Member,,,,,(2026-08-25)\n",
            to: "Master_AdultHistory.csv"
        )
        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22", clock: { [clock] in clock.now })
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

        // Signing in twice in a day records the day once, and a form that
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
        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        let chris = try reopened.registerAdult(["First": "Chris", "Last": "Chair", "UnitType": "Troop", "Unit": "7", "FinalBoard": "Nonsense"])
        #expect(chris.canChair(.finalBoard), "taken from the history")
        #expect(chris.role(for: .projectReview) == .member)
        let newcomer = try reopened.registerAdult(["First": "New", "Last": "Person", "UnitType": "Troop", "Unit": "8"])
        #expect(newcomer.role(for: .finalBoard) == .member && newcomer.role(for: .projectReview) == .member)
    }

    // An adult who would rather not use the tablet, added on the Adults page
    // (Java event test section 27).
    @Test func anAdultAddedByHandIsSignedInAsTheTabletWould() throws {
        try scratch.write(
            "Type,ID,Last,First,Email,Phone,UnitType,Unit,UnitName,ProjectReview,FinalBoard,RegTime,Room,Flags,Sel,BoardHistory\n"
                + "ADULT,ADULT:Chair:Chris:7,Chair,Chris,chris@example.org,,Troop,7,Troop7,Member,Chair,,,,,(2026-08-25)\n",
            to: "Master_AdultHistory.csv"
        )
        let clock = self.clock
        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22", clock: { clock.now })
        let chris = try reopened.registerAdult(Adult.handSignInForm(
            first: "Chris", last: "Chair", email: "", phone: "", unitType: "Troop", unit: "7",
            finalBoard: nil, projectReview: .chair, woodBadge: true
        ))
        #expect(chris.canChair(.finalBoard), "As Last Time keeps the Chair on file")
        #expect(chris.canChair(.projectReview), "a role chosen in the sheet is used")
        #expect(chris.woodBadge == "Y")
        #expect(reopened.adults.map(\.id) == ["ADULT:Chair:Chris:7"], "the same record the history holds")
        #expect(reopened.adultHistory.count == 1 && reopened.adultHistory[0].boardHistory == "(2026-08-25)(2026-09-22)")

        let dana = try reopened.registerAdult(Adult.handSignInForm(
            first: "Dana", last: "District", email: "", phone: "", unitType: "District", unit: "12",
            finalBoard: nil, projectReview: nil, woodBadge: false
        ))
        #expect(dana.unit == "" && dana.role(for: .finalBoard) == .member, "someone new is a Member")
        #expect(throws: EventError.self, "a name is still required") {
            try reopened.registerAdult(Adult.handSignInForm(
                first: "", last: "Nobody", email: "", phone: "", unitType: "Troop", unit: "1",
                finalBoard: nil, projectReview: nil, woodBadge: false
            ))
        }
    }

    // The Add Adult sheet fills itself in from the adult history.
    @Test func theHistoryIsSearchedByNameEmailAndUnit() throws {
        try scratch.write(
            "Type,ID,Last,First,Email,Phone,UnitType,Unit,UnitName,ProjectReview,FinalBoard,RegTime,Room,Flags,Sel,BoardHistory\n"
                + "ADULT,ADULT:Chair:Chris:7,Chair,Chris,chris@example.org,,Troop,7,Troop7,Member,Chair,,,,,(2026-08-25)\n"
                + "ADULT,ADULT:Able:Ann:12,Able,Ann,ann@example.org,,Crew,12,Crew12,Member,Member,,,,,(2026-08-25)\n"
                + "ADULT,ADULT:Chairez:Pat:7,Chairez,Pat,,,Troop,7,Troop7,Chair,Member,,,,,(2026-07-28)\n",
            to: "Master_AdultHistory.csv"
        )
        let clock = self.clock
        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22", clock: { clock.now })
        #expect(reopened.historyMatches(for: "chair").map(\.first) == ["Chris", "Pat"], "by last name, then first")
        #expect(reopened.historyMatches(for: "chair pat").map(\.first) == ["Pat"], "every word must match")
        #expect(reopened.historyMatches(for: "ANN@EXAMPLE").map(\.first) == ["Ann"])
        #expect(reopened.historyMatches(for: "T7").count == 2, "the unit as the lists show it")
        #expect(reopened.historyMatches(for: "  ").isEmpty)
        #expect(reopened.historyMatches(for: "e", limit: 2).count == 2)

        // Filled in from Chris's record, with the first name corrected.
        let chris = try reopened.registerAdult(Adult.handSignInForm(
            historyID: "ADULT:Chair:Chris:7", first: "Christopher", last: "Chair", email: "chris@example.org", phone: "",
            unitType: "Troop", unit: "7", finalBoard: .chair, projectReview: .member, woodBadge: false
        ))
        #expect(chris.id == "ADULT:Chair:Chris:7" && chris.first == "Christopher")
        #expect(reopened.adultHistory.count == 3, "the same history record, not a new one")
    }

    // SPEC.md P-6: an adult's name, unit, contact and roles are one set of
    // facts in the event's adults and the read-only adult history; an edit on
    // the Adults page reaches the history, and Wood Badge stays with the event.
    @Test func anEditOnTheAdultsPageReachesTheHistory() throws {
        let adult = try event.registerAdult(["First": "Morgan", "Last": "Member", "UnitType": "Troop", "Unit": "9",
                                             "Email": "morgan@example.org", "WoodBadge": "Y"])
        var edited = try #require(event.adult(id: adult.id))
        edited.finalBoardRoleText = "Chair"
        edited.email = ""
        edited.unit = "19"
        edited.woodBadge = ""
        try event.updateAdult(edited)
        let kept = try #require(event.adultHistory.first { $0.id == adult.id })
        #expect(kept.canChair(.finalBoard), "a chair promoted today is one at the next sign-in")
        #expect(kept.email == "" && kept.unitName == "Troop19", "a cleared field reaches the history too")
        #expect(kept.boardHistory == "(2026-09-22)", "the history's own columns are left alone")

        let reopened = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
        #expect(reopened.adult(id: adult.id)?.canChair(.finalBoard) == true, "both files are saved")
        #expect(reopened.adultHistory.first { $0.id == adult.id }?.unit == "19")

        try event.deleteAdult(id: adult.id)
        #expect(event.adult(id: adult.id) == nil && event.adultHistory.contains { $0.id == adult.id },
                "taking someone off the event's list leaves the history alone")
    }

    @Test func signingInAgainDoesNotTakeAnAdultOffTheirBoard() throws {
        var adult = try event.registerAdult(["First": "Morgan", "Last": "Member", "UnitType": "Troop", "Unit": "9"])
        adult.room = "101"
        try event.updateAdult(adult)
        let again = try event.registerAdult(["First": "Morgan", "Last": "Member", "UnitType": "Troop", "Unit": "9", "Phone": "333"])
        #expect(again.room == "101")
        #expect(again.phone == "333")
    }

    @Test func unitlessAdultsHaveNoUnitNumber() throws {
        let adult = try event.registerAdult(["First": "Dana", "Last": "District", "UnitType": "District", "Unit": "12"])
        #expect(adult.unit == "")
        #expect(adult.unitName == "District")
        #expect(adult.unitLabel == "District")
        #expect(adult.unitDisplay == "District")
    }

    @Test func unitDisplayAddsTheSpaceUnitNameLeavesOut() throws {
        let adult = try event.registerAdult(["First": "Chris", "Last": "Chair", "UnitType": "Troop", "Unit": "7"])
        #expect(adult.unitName == "Troop7")
        #expect(adult.unitDisplay == "Troop 7")
    }

    @Test func blankOrNoneEmailsNeverMatch() throws {
        try event.registerAdult(["First": "No", "Last": "Email", "Email": "NONE", "UnitType": "Troop", "Unit": "1"])
        #expect(event.knownAdult(matchingEmail: "none") == nil)
        #expect(event.knownAdult(matchingEmail: "") == nil)
    }

    @Test func minutesRunFromTheLastChange() throws {
        let youth = try event.registerYouth(youthForm("Jan", "Doe", email: "jan@example.org"))
        clock.advance(minutes: 12)
        #expect(event.scout(id: youth.id)?.minutesSinceLastUpdate(now: event.now) == 12)
        try event.postponeBoard(scoutID: youth.id)
        #expect(event.scout(id: youth.id)?.minutesSinceLastUpdate(now: event.now) == 0, "a status change restarts the clock")
    }
}

@MainActor
@Suite("Rooms")
struct RoomTests {
    let scratch: ScratchFolder
    let event: BoardEvent

    init() throws {
        scratch = try ScratchFolder()
        event = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
    }

    @Test func roomsAreUniqueAndNamed() throws {
        try event.addRoom(named: " 101 ", boardType: .finalBoard)
        #expect(event.room(id: "ROOM:101")?.name == "101")
        #expect(throws: EventError.self) { try event.addRoom(named: "101", boardType: .projectReview) }
        #expect(throws: EventError.self) { try event.addRoom(named: "  ", boardType: .projectReview) }
        #expect(throws: EventError.self) { try event.addRoom(named: "1,2", boardType: .projectReview) }

        #expect(throws: EventError.self) { try event.swapRooms("ROOM:101", "ROOM:101") }
    }

    @Test func swappingMovesTheYouthTheMembersAndTheCard() throws {
        try event.addRoom(named: "101", boardType: .finalBoard)
        try event.addRoom(named: "102", boardType: .finalBoard)
        for (first, role) in [("Chris", "Chair"), ("Morgan", "Member"), ("Taylor", "Member")] {
            try event.registerAdult(["First": first, "Last": "Adult", "UnitType": "Troop", "Unit": first.count.description + "0", "FinalBoard": role])
        }
        let youth = try event.registerYouth(["First": "Jan", "Last": "Doe", "UnitType": "Troop", "Unit": "1776", "BoardType": "Final"])
        let adultIDs = event.adults.map(\.id)
        try event.seatBoard(roomID: "ROOM:101", scoutID: youth.id, chairID: adultIDs[0], memberIDs: adultIDs)

        try event.swapRooms("ROOM:101", "ROOM:102")
        #expect(event.scout(id: youth.id)?.room == "102")
        #expect(event.adults.allSatisfy { $0.room == "102" })
        #expect(event.room(named: "102")?.scoutName == "Jan Doe")
        #expect(event.room(named: "101")?.isFree == true)
        #expect(throws: EventError.self) { try event.removeRoom(id: "ROOM:102") }
        try event.removeRoom(id: "ROOM:101")
        #expect(event.rooms.map(\.name) == ["102"])
    }

    @Test func roomsCopyFromAnEarlierEventEmpty() throws {
        try scratch.write(
            "Type,ID,Room,BoardType,Scout,Leaders,RegTime\nROOM,ROOM:101,101,Final,Old Youth,Old Adults,\nROOM,ROOM:200A,200A,Project,,,\n",
            to: "2026-08-25/rooms.csv"
        )
        try event.addRoom(named: "101", boardType: .finalBoard)
        #expect(try event.copyRooms(fromEvent: "2026-08-25") == 1)
        #expect(event.rooms.map(\.name) == ["101", "200A"])
        #expect(event.rooms.allSatisfy { $0.isFree })
        #expect(scratch.dataFolder.events() == ["2026-09-22", "2026-08-25"])
    }
}

@MainActor
@Suite("SignUpGenius import")
struct SignUpImportTests {
    let scratch: ScratchFolder
    let event: BoardEvent

    init() throws {
        scratch = try ScratchFolder()
        event = try BoardEvent(folder: scratch.dataFolder, date: "2026-09-22")
    }

    @Test func entriesBecomeHistoryAndPreRegistrations() throws {
        try event.registerAdult(["First": "Known", "Last": "Adult", "Email": "known@example.org", "UnitType": "Troop", "Unit": "1", "Phone": "old"])
        let summary = try event.mergeSignUps([
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
        #expect(event.knownAdult(matchingEmail: "known@example.org")?.phone == "770-555-0100")

        let added = try #require(event.knownAdult(matchingEmail: "new@example.org"))
        #expect(added.fullName == "New Van dyke")
        #expect(added.unitName == "Crew55")
        #expect(added.phone == "770-555-0101")
        #expect(added.role(for: .finalBoard) == .member && added.role(for: .projectReview) == .member)

        let jan = try #require(event.scheduledYouth(matchingEmail: "jan@example.org"))
        #expect(jan.id == "SCOUT:Doe:Jan:1776")
        #expect(jan.boardType == .finalBoard)
        #expect(jan.leader == "Lee Leader")
        #expect(jan.phone == "", "a youth's phone number is not imported (D-8)")
        #expect(event.scheduledYouth(matchingEmail: "sam@example.org")?.boardType == .projectReview)
        #expect(event.scheduledYouth(matchingEmail: "sam@example.org")?.unitName == "Post9")

        // Importing the same sign-up again adds nobody.
        let again = try event.mergeSignUps([
            SignUpEntry(startDate: "2026-09-22", firstName: "jan", lastName: "doe", item: "Eagle Board of Review",
                        email: "jan@example.org", customAnswers: []),
        ], month: "2026-09")
        #expect(again.alreadyScheduledYouth == 1)
        #expect(event.scheduledScouts.count == 2)
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
