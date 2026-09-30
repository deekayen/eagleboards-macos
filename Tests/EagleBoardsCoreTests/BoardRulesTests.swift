import EagleBoardsCore
import Testing

// The composition rules as pure functions, where only the Mac has them. The
// rules all three versions share -- same-unit members, the national floor,
// board sizes, the suggestion, fill the rest and the Supporting link -- are
// the shared cases (SharedCaseTests). These cover the pieces the Mac app
// adds: the one-pass seating review, the suggestion's room, locating leaders
// and parents, the room timers, the next step, who can join a board, and
// finding a person's room.

private func adult(
    _ first: String, _ last: String, unitName: String,
    final finalRole: BoardRole = .member, project projectRole: BoardRole = .member, room: String = "",
    supporting: String = ""
) -> Adult {
    Adult(fields: [
        "Type": "ADULT", "ID": "ADULT:\(last):\(first)", "First": first, "Last": last,
        "UnitName": unitName, "FinalBoard": finalRole.rawValue, "ProjectReview": projectRole.rawValue, "Room": room,
        "Supporting": supporting,
    ])
}

private func scout(
    _ first: String = "Casey", _ last: String = "Candidate", unitName: String = "Troop1234",
    boardType: BoardType = .finalBoard, status: BoardStatus = .registered, leader: String = ""
) -> Scout {
    Scout(fields: [
        "Type": "SCOUT", "ID": "SCOUT:\(last):\(first)", "First": first, "Last": last, "UnitName": unitName,
        "BoardType": boardType.rawValue, "Status": status.rawValue, "Leader": leader,
    ])
}

private func room(_ name: String, _ boardType: BoardType, scoutName: String = "") -> Room {
    Room(fields: ["Type": "ROOM", "ID": "ROOM:\(name)", "Room": name, "BoardType": boardType.rawValue, "Scout": scoutName])
}

private func names(_ adults: [Adult]) -> [String] { adults.map(\.fullName) }

@Suite("Seating review")
struct SeatingReviewTests {
    let finalRoom = room("101", .finalBoard)

    @Test func aGoodBoardHasNothingToSay() {
        let members = [
            adult("Chris", "Chair", unitName: "Troop1", final: .chair),
            adult("Morgan", "Member", unitName: "Troop2"),
            adult("Taylor", "Member", unitName: "Troop3"),
        ]
        let review = SeatingReview(scout: scout(), members: members, room: finalRoom)
        #expect(review.canSeat)
        #expect(review.warnings.isEmpty)
        #expect(names(review.qualifiedChairs) == ["Chris Chair"])
    }

    @Test func onlyQualifiedChairsAreOffered() {
        let members = [
            adult("Chris", "Chair", unitName: "Troop1", final: .chair),
            adult("Pat", "Projectchair", unitName: "Troop2", project: .chair),
            adult("Taylor", "Member", unitName: "Troop3"),
        ]
        let review = SeatingReview(scout: scout(), members: members, room: finalRoom)
        #expect(names(review.qualifiedChairs) == ["Chris Chair"])
    }

    @Test func noQualifiedChairIsBlocking() {
        let members = ["A", "B", "C"].map { adult($0, "Member", unitName: "Troop9") }
        let review = SeatingReview(scout: scout(), members: members, room: finalRoom)
        #expect(!review.canSeat)
        #expect(review.blockingProblems.contains { $0.contains("qualified to chair") })
    }

    @Test func sameUnitMembersWarnButDoNotBlock() {
        let members = [
            adult("Chris", "Chair", unitName: "Troop9", final: .chair),
            adult("Robin", "Sameunit", unitName: "Troop1234"),
            adult("Taylor", "Member", unitName: "Troop3"),
        ]
        let review = SeatingReview(scout: scout(), members: members, room: finalRoom)
        #expect(review.canSeat)
        #expect(review.warnings.count == 1)
        #expect(review.warnings[0].detail.contains("Robin Sameunit"))
    }

    @Test func anAllSameUnitBoardIsRefusedOutright() {
        let members = [
            adult("Chris", "Chair", unitName: "Troop1234", final: .chair),
            adult("Robin", "Sameunit", unitName: "Troop1234"),
            adult("Alex", "Sameunit", unitName: "Troop1234"),
        ]
        let review = SeatingReview(scout: scout(), members: members, room: finalRoom)
        #expect(!review.canSeat)
        #expect(review.blockingProblems.contains { $0.contains("8.0.3.0") })
    }

    @Test func fourMembersAsksForConfirmationSevenIsRefused() {
        let chair = adult("Chris", "Chair", unitName: "Troop1", final: .chair)
        let four = [chair] + ["A", "B", "C"].map { adult($0, "Member", unitName: "Troop5") }
        let fourReview = SeatingReview(scout: scout(), members: four, room: finalRoom)
        #expect(fourReview.canSeat)
        #expect(fourReview.warnings.contains { $0.title.contains("4 members") })

        let seven = [chair] + ["A", "B", "C", "D", "E", "F"].map { adult($0, "Member", unitName: "Troop5") }
        #expect(!SeatingReview(scout: scout(), members: seven, room: finalRoom).canSeat)
    }

    @Test func disabledAndBusyAndUnavailableAdultsBlock() {
        let chair = adult("Chris", "Chair", unitName: "Troop1", final: .chair)
        let gone = adult("Gone", "Home", unitName: "Troop2", room: disabledForTodayMarker)
        let busy = adult("Busy", "Elsewhere", unitName: "Troop3", room: "102")
        let unavailable = adult("Not", "Today", unitName: "Troop4", final: .unavailable)
        let review = SeatingReview(scout: scout(), members: [chair, gone, busy, unavailable], room: finalRoom)
        #expect(review.blockingProblems.contains { $0.contains("disabled for today") })
        #expect(review.blockingProblems.contains { $0.contains("room 102") })
        #expect(review.blockingProblems.contains { $0.contains("unavailable") })
    }

    @Test func wrongRoomTypeWarnsOccupiedRoomBlocks() {
        let members = [
            adult("Chris", "Chair", unitName: "Troop1", final: .chair),
            adult("Morgan", "Member", unitName: "Troop2"),
            adult("Taylor", "Member", unitName: "Troop3"),
        ]
        let projectRoom = SeatingReview(scout: scout(), members: members, room: room("200A", .projectReview))
        #expect(projectRoom.canSeat)
        #expect(projectRoom.warnings.contains { $0.title.contains("200A") })

        let occupied = SeatingReview(scout: scout(), members: members, room: room("101", .finalBoard, scoutName: "Someone Else"))
        #expect(!occupied.canSeat)

        #expect(!SeatingReview(scout: scout(), members: members, room: nil).canSeat)
    }

    @Test(arguments: [BoardStatus.seated, .inProgress, .completed, .postponed])
    func onlyAWaitingYouthCanBeSeated(status: BoardStatus) {
        let members = [
            adult("Chris", "Chair", unitName: "Troop1", final: .chair),
            adult("Morgan", "Member", unitName: "Troop2"),
            adult("Taylor", "Member", unitName: "Troop3"),
        ]
        #expect(!SeatingReview(scout: scout(status: status), members: members, room: finalRoom).canSeat)
    }

    @Test func aLegacyVerifiedYouthCanStillBeSeated() {
        let members = [
            adult("Chris", "Chair", unitName: "Troop1", final: .chair),
            adult("Morgan", "Member", unitName: "Troop2"),
            adult("Taylor", "Member", unitName: "Troop3"),
        ]
        #expect(SeatingReview(scout: scout(status: .verified), members: members, room: finalRoom).canSeat)
    }
}

@Suite("Board suggestion")
struct BoardSuggestionTests {
    @Test func picksAChairTwoMembersAndAFreeRoomOfTheRightKind() {
        let adults = [
            adult("Robin", "Sameunit", unitName: "Troop1234", final: .chair),
            adult("Busy", "Chair", unitName: "Troop7", final: .chair, room: "105"),
            adult("Chris", "Chair", unitName: "Troop1", final: .chair),
            adult("Gone", "Home", unitName: "Troop8", room: disabledForTodayMarker),
            adult("Morgan", "Member", unitName: "Troop2"),
            adult("Taylor", "Member", unitName: "Troop3"),
            adult("Extra", "Member", unitName: "Troop4"),
        ]
        let rooms = [room("200A", .projectReview), room("101", .finalBoard, scoutName: "Taken"), room("102", .finalBoard)]
        let suggestion = BoardSuggestion(for: scout(), adults: adults, rooms: rooms)
        #expect(suggestion.chairID == "ADULT:Chair:Chris")
        #expect(suggestion.memberIDs == ["ADULT:Chair:Chris", "ADULT:Member:Morgan", "ADULT:Member:Taylor"])
        #expect(suggestion.roomID == "ROOM:102")
        #expect(suggestion.problems.isEmpty)
    }

    @Test func shortagesAreReported() {
        let suggestion = BoardSuggestion(for: scout(), adults: [adult("Morgan", "Member", unitName: "Troop3")], rooms: [])
        #expect(suggestion.chairID == nil)
        #expect(suggestion.problems.count == 3)
    }
}

@Suite("Locating leaders and parents")
struct AdultLocatorTests {
    @Test func findsTheLeaderByNameAndUnitAndAParentByLastName() {
        let youth = scout("Casey", "Candidate", unitName: "Troop1234", leader: "Lee Leader")
        let adults = [
            adult("Lee", "Leader", unitName: "Troop1234"),
            adult("Jamie", "Candidate", unitName: "Troop1234"),
            adult("Jamie", "Candidate", unitName: "Troop9999"),
            adult("Stranger", "Danger", unitName: "Troop1234"),
        ]
        let found = AdultLocator.locate(for: youth, among: adults)
        #expect(found.map(\.adult.fullName) == ["Lee Leader", "Jamie Candidate"])
        #expect(found.map(\.relation) == [.leader, .parent])
    }

    @Test func aLeaderFromAnotherUnitMatchesOnFirstAndLastName() {
        let youth = scout(unitName: "Troop1234", leader: "Lee Coach")
        let found = AdultLocator.locate(for: youth, among: [adult("Lee", "Coach", unitName: "Crew55")])
        #expect(found.map(\.relation) == [.leader])
    }

    @Test func anAdultWithNoLastNameIsNeverALeader() {
        let youth = scout(leader: "Anybody")
        #expect(AdultLocator.locate(for: youth, among: [adult("Nobody", "", unitName: "Troop5")]).isEmpty)
    }

    // SPEC.md D-23, after the 2026-09-30 event: the cases Windows'
    // SchedulerLogicTests and Java's test-board-builder.js run too.
    @Test func startReviewNamesWhoIntroducesTheYouthOnABoardOfReviewNeverAParent() throws {
        let youth = scout("Casey", "Candidate", unitName: "Troop1234", leader: "Lee Leader")
        let leader = adult("Lee", "Leader", unitName: "Troop1234")
        let parent = adult("Jamie", "Candidate", unitName: "Troop1234")
        let introducer = adult("Sam", "Scoutmaster", unitName: "Troop1234", room: "104", supporting: "SCOUT:X|\(youth.id)")

        // Linked: only whoever introduces them, not the leader or parent besides.
        let linked = try #require(AdultLocator.introduction(for: youth, among: [leader, parent, introducer]))
        #expect(linked.map(\.adult.fullName) == ["Sam Scoutmaster"])
        #expect(AdultLocator.introductionText(for: youth, among: [leader, parent, introducer])
            == "\n\nFirst fetch whoever introduces them to the board:\nSam Scoutmaster (Room 104)")

        // No one linked: their leader, if signed in, still never the parent.
        let unlinked = try #require(AdultLocator.introduction(for: youth, among: [leader, parent]))
        #expect(unlinked.map(\.adult.fullName) == ["Lee Leader"])
        #expect(unlinked.map(\.relation) == [.leader])

        // Only a parent here: no one to name, but still a reminder.
        let parentOnly = try #require(AdultLocator.introduction(for: youth, among: [parent]))
        #expect(parentOnly.isEmpty)
        #expect(AdultLocator.introductionText(for: youth, among: [parent])
            == "\n\nNo one has said they'll introduce them, and their leader hasn't signed in. Ask Casey who will.")
    }

    @Test func aProjectReviewHasNoIntroductionToRemindAbout() {
        let youth = scout(boardType: .projectReview, leader: "Lee Leader")
        let introducer = adult("Sam", "Scoutmaster", unitName: "Troop1234", supporting: youth.id)
        #expect(AdultLocator.introduction(for: youth, among: [introducer]) == nil)
        #expect(AdultLocator.introductionText(for: youth, among: [introducer]).isEmpty)
    }
}

@Suite("Room timers")
struct RoomTimerTests {
    let config = Config.standard

    @Test func convenesHaveARedLimitAndNoYellow() {
        #expect(RoomTimer.state(status: .seated, boardType: .finalBoard, minutes: 29, config: config) == .okay)
        #expect(RoomTimer.state(status: .seated, boardType: .finalBoard, minutes: 30, config: config) == .overdue)
    }

    @Test func finalBoardsGoYellowAtThirtyAndRedAtFortyFive() {
        #expect(RoomTimer.state(status: .inProgress, boardType: .finalBoard, minutes: 29, config: config) == .okay)
        #expect(RoomTimer.state(status: .inProgress, boardType: .finalBoard, minutes: 30, config: config) == .warning)
        #expect(RoomTimer.state(status: .inProgress, boardType: .finalBoard, minutes: 45, config: config) == .overdue)
    }

    @Test func projectReviewsGoYellowAtTwentyFiveAndRedAtForty() {
        #expect(RoomTimer.state(status: .inProgress, boardType: .projectReview, minutes: 25, config: config) == .warning)
        #expect(RoomTimer.state(status: .inProgress, boardType: .projectReview, minutes: 40, config: config) == .overdue)
    }

    @Test func nothingElseIsTimed() {
        #expect(RoomTimer.state(status: .registered, boardType: .finalBoard, minutes: 500, config: config) == nil)
        #expect(RoomTimer.state(status: .completed, boardType: .finalBoard, minutes: 500, config: config) == nil)
        var off = config
        off.conveneRedMinutes = 0
        #expect(RoomTimer.state(status: .seated, boardType: .finalBoard, minutes: 500, config: off) == nil)
    }
}

/// The scheduler's Next Step button and Return key follow the lifecycle.
@Suite("The next step for a board")
struct NextStepTests {
    @Test(arguments: [
        (BoardStatus.registered, BoardStep?.some(.seat)),
        (.verified, .seat),
        (.seated, .startReview),
        (.inProgress, .complete),
        (.completed, nil),
        (.postponed, nil),
    ])
    func eachStatusHasOneNextStep(status: BoardStatus, step: BoardStep?) {
        #expect(status.nextStep == step)
    }
}

/// Who the board being drawn up offers: never someone Seat Board refuses.
@Suite("Adults who can join a board")
struct CanJoinTests {
    @Test func aFreeMemberCanJoin() {
        #expect(adult("Free", "Member", unitName: "Troop1").canJoin(.finalBoard))
    }

    @Test func noThanksToOneKindStillAllowsTheOther() {
        let projectOnly = adult("Project", "Only", unitName: "Troop1", final: .unavailable)
        #expect(!projectOnly.canJoin(.finalBoard))
        #expect(projectOnly.canJoin(.projectReview))
    }

    @Test func someoneOnABoardOrGoneHomeCannotJoin() {
        #expect(!adult("On", "Board", unitName: "Troop1", room: "201").canJoin(.finalBoard))
        #expect(!adult("Gone", "Home", unitName: "Troop1", room: disabledForTodayMarker).canJoin(.finalBoard))
    }
}

// SPEC.md D-21, with the Windows version's test cases
// (SchedulerLogicTests.FindingAPersonSaysWhichRoomTheyAreInOrWhereTheyAreInstead).
@Suite("Finding a person's room")
struct PersonFindTests {
    private func youth(_ first: String, _ last: String, _ status: BoardStatus, room: String = "") -> Scout {
        var record = scout(first, last, status: status)
        record.room = room
        return record
    }

    private var signedIn: (youth: [Scout], adults: [Adult]) {
        (
            [
                youth("Arthur", "Eldred", .inProgress, room: "101"),
                youth("Bill", "Amend", .registered),
                youth("Peter", "Agre", .completed, room: disabledForTodayMarker),
                youth("Rob", "Corddry", .postponed),
            ],
            [
                adult("Neil", "Armstrong", unitName: "Troop2", room: "101"),
                adult("Jim", "Lovell", unitName: "Troop2"),
                adult("Charles", "Duke", unitName: "Troop2", room: disabledForTodayMarker),
            ]
        )
    }

    private func say(_ query: String) -> String {
        PersonFind.people(query, youth: signedIn.youth, adults: signedIn.adults)
            .map { "\($0.name) \($0.whereabouts)\($0.room.map { " [\($0)]" } ?? "")" }
            .joined(separator: "; ")
    }

    @Test func aPersonIsFoundInTheirRoomOrWhereTheyAreInstead() {
        #expect(say("ar") == "Arthur Eldred is in room 101 [101]; Neil Armstrong is in room 101 [101]; Charles Duke has gone home",
                "youth first, then adults, each by last name")
        #expect(say("neil arm") == "Neil Armstrong is in room 101 [101]")
        #expect(say("bill") == "Bill Amend is waiting")
        #expect(say("AGRE") == "Peter Agre has finished")
        #expect(say("rob c") == "Rob Corddry was postponed")
        #expect(say("lovell") == "Jim Lovell isn't on a board")
        #expect(say("Duke") == "Charles Duke has gone home")
        #expect(say("  ").isEmpty && say("Spielberg").isEmpty)
    }

    @Test func theFindNarrowsTheRoomsAndSaysWhereTheRestAre() {
        let rooms = [room("101", .finalBoard, scoutName: "Arthur Eldred"), room("102", .finalBoard), room("200A", .projectReview)]
        func find(_ query: String) -> (rooms: Set<String>?, note: String?) {
            let found = PersonFind.people(query, youth: signedIn.youth, adults: signedIn.adults)
            let shown = PersonFind.rooms(query, people: found, rooms: rooms)
            return (shown, PersonFind.note(people: found, roomsFound: shown))
        }
        #expect(find("").rooms == nil && find("").note == nil, "an empty find shows every room")
        #expect(find("armstrong").rooms == ["101"] && find("armstrong").note == nil)
        #expect(find("20").rooms == ["200A"], "a room by its name")
        #expect(find("ar").rooms == ["101"] && find("ar").note == "Charles Duke has gone home.")
        #expect(find("bill").rooms == [] && find("bill").note == "Bill Amend is waiting.")
        #expect(find("Spielberg").note == "No one by that name has signed in.")
        let crowd = (1...6).map { youth("Pat", "Waiting\($0)", .registered) }
        let found = PersonFind.people("pat", youth: crowd, adults: [])
        #expect(PersonFind.note(people: found, roomsFound: PersonFind.rooms("pat", people: found, rooms: rooms))
                == "Pat Waiting1 is waiting. Pat Waiting2 is waiting. Pat Waiting3 is waiting. Pat Waiting4 is waiting. And 2 more.")
    }
}
