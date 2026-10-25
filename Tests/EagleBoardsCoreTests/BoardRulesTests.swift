import EagleBoardsCore
import Foundation
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
        #expect(review.blockingProblems.contains(
            "None of the members can chair a Final Board. Add a qualified chair, or make someone a chair on the Adults page."))
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
        #expect(review.warnings[0].title == "1 member is from Casey Candidate's unit")
        // SPEC.md O-1: the screen says youth. Short sentences with nothing
        // nested, for reading aloud, and the unit in full (Windows c0b18db).
        #expect(review.warnings[0].detail == "Robin Sameunit is in Troop 1234, the youth's own unit. This council "
            + "doesn't allow that. The national rule needs only one member from outside the unit, and this board meets it.")
    }

    @Test func anAllSameUnitBoardIsRefusedOutright() {
        let members = [
            adult("Chris", "Chair", unitName: "Troop1234", final: .chair),
            adult("Robin", "Sameunit", unitName: "Troop1234"),
            adult("Alex", "Sameunit", unitName: "Troop1234"),
        ]
        let review = SeatingReview(scout: scout(), members: members, room: finalRoom)
        #expect(!review.canSeat)
        #expect(review.blockingProblems.contains("Every selected member is in Troop 1234, Casey Candidate's own unit. "
            + "A board needs at least one member from outside the unit (Guide to Advancement 8.0.3.0). Add someone from another unit."))
    }

    @Test func fourMembersAsksForConfirmationSevenIsRefused() {
        let chair = adult("Chris", "Chair", unitName: "Troop1", final: .chair)
        let four = [chair] + ["A", "B", "C"].map { adult($0, "Member", unitName: "Troop5") }
        let fourReview = SeatingReview(scout: scout(), members: four, room: finalRoom)
        #expect(fourReview.canSeat)
        #expect(fourReview.warnings.contains { $0.title.contains("4 members") })

        let seven = [chair] + ["A", "B", "C", "D", "E", "F"].map { adult($0, "Member", unitName: "Troop5") }
        #expect(SeatingReview(scout: scout(), members: seven, room: finalRoom).blockingProblems
            == ["A Final Board can have at most 6 (Guide to Advancement 8.0.0.3). Remove 1."])
    }

    /// Each problem ends with what to do about it.
    @Test func tooFewSaysHowManyMore() {
        let chair = adult("Chris", "Chair", unitName: "Troop1", final: .chair, project: .chair)
        #expect(SeatingReview(scout: scout(), members: [chair, adult("A", "Member", unitName: "Troop5")], room: finalRoom)
            .blockingProblems == ["A Final Board needs at least 3. Add 1 more."])
        #expect(SeatingReview(scout: scout(boardType: .projectReview), members: [chair], room: room("200A", .projectReview))
            .blockingProblems == ["A Proposal Review needs at least 2. Add 1 more."])
        #expect(SeatingReview(scout: scout(), members: [], room: finalRoom).blockingProblems
            == ["No one is on the board yet. Add at least 3 members."])
        var seated = scout(status: .seated)
        seated.room = "101"
        #expect(ChangeMembersReview(scout: seated, members: []).blockingProblems
            == ["No one is left on the board. Add at least 3 members."])
    }

    @Test func disabledAndBusyAndUnavailableAdultsBlock() {
        let chair = adult("Chris", "Chair", unitName: "Troop1", final: .chair)
        let gone = adult("Gone", "Home", unitName: "Troop2", room: disabledForTodayMarker)
        let busy = adult("Busy", "Elsewhere", unitName: "Troop3", room: "102")
        let unavailable = adult("Not", "Today", unitName: "Troop4", final: .unavailable)
        let review = SeatingReview(scout: scout(), members: [chair, gone, busy, unavailable], room: finalRoom)
        #expect(review.blockingProblems == [
            "Gone Home has gone home. Remove them, or bring them back with Adult › Mark Back.",
            "Busy Elsewhere is on the board in room 102. Remove them.",
            "Not Today said no thanks to Final Boards. Remove them.",
        ])
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

        let occupied = SeatingReview(scout: scout(), members: members, room: room("101", .finalBoard, scoutName: "Someone~ Else"))
        #expect(occupied.blockingProblems == ["Room 101 already has Someone, Else's board. Choose a free room."],
                "the youth's name with its comma (SPEC.md D-1)")

        #expect(SeatingReview(scout: scout(), members: members, room: nil).blockingProblems == ["Choose a free room."])
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

    /// The refusal names the column by its heading on the Youth page, and
    /// the types as its menu offers them, not the file's Final or Project.
    @Test func noBoardTypeSaysWhichColumnToSetIt() {
        let youth = Scout(fields: [
            "Type": "SCOUT", "ID": "SCOUT:Candidate:Casey", "First": "Casey", "Last": "Candidate",
            "UnitName": "Troop1234", "BoardType": "", "Status": BoardStatus.registered.rawValue,
        ])
        let review = SeatingReview(scout: youth, members: [], room: finalRoom)
        #expect(review.blockingProblems.contains {
            $0 == "Casey Candidate has no board type. Set Final Board or Proposal Review in the Board Type column of the Youth page."
        })
        #expect(SeatingReview.noBoardType("Casey Candidate") == review.blockingProblems.last)
    }

    /// The seating sheets name the Adults page's role column for the board's
    /// type, as its heading reads.
    @Test func whoMayChairNamesTheRoleColumn() {
        #expect(SeatingReview.whoMayChair(.finalBoard) == "Only members whose Final Board Role is Chair may chair.")
        #expect(SeatingReview.whoMayChair(.projectReview) == "Only members whose Proposal Review Role is Chair may chair.")
    }
}

/// The inspector's notes as VoiceOver reads them, and which are said as
/// they appear (Windows' ShowIssues reads "Error:" or "Warning:").
@Suite("Seating review, read aloud")
struct SeatingReviewSpokenTests {
    @Test func eachNoteSaysWhetherItStopsTheBoard() throws {
        let members = [
            adult("Chris", "Chair", unitName: "Troop1", final: .chair),
            adult("Morgan", "Member", unitName: "Troop2"),
            adult("Taylor", "Member", unitName: "Troop3"),
        ]
        let warning = try #require(SeatingReview(scout: scout(), members: members, room: room("200A", .projectReview)).warnings.first)
        #expect(SeatingReview.spoken(problem: "Choose a free room.") == "Cannot seat yet: Choose a free room.")
        #expect(SeatingReview.spoken(warning: warning)
                == "Check before seating: Room 200A is a Proposal Review room. Casey Candidate is here for a Final Board.")
        #expect(SeatingReview.spoken(problems: ["Choose a free room."], warnings: [warning])
                == ["Cannot seat yet: Choose a free room.", SeatingReview.spoken(warning: warning)], "problems first, as shown")
    }

    @Test func onlyANoteThatAppearedIsSaid() {
        let before = ["Cannot seat yet: A Final Board needs at least 3. Add 1 more."]
        let after = ["Cannot seat yet: Choose a free room.", before[0]]
        #expect(SeatingReview.newlySpoken(after, since: before) == "Cannot seat yet: Choose a free room.")
        #expect(SeatingReview.newlySpoken(before, since: after).isEmpty, "one that went away is not said")
        #expect(SeatingReview.newlySpoken(["A.", "B."], since: []) == "A. B.", "several, in one announcement")
    }

    /// The live review's own problems, read with their prefix.
    @Test func aRealReviewReadsWithItsPrefix() {
        let members = ["A", "B", "C"].map { adult($0, "Member", unitName: "Troop9") }
        let review = SeatingReview(scout: scout(), members: members, room: nil)
        #expect(SeatingReview.spoken(problems: review.blockingProblems, warnings: review.warnings) == [
            "Cannot seat yet: None of the members can chair a Final Board. Add a qualified chair, or make someone a chair on the Adults page.",
            "Cannot seat yet: Choose a free room.",
        ])
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

    /// The last-name guard alone: in the youth's own unit, an adult with no
    /// last name would match any leader without it, since every leader text
    /// contains the empty string.
    @Test func anAdultInTheYouthsUnitWithNoLastNameIsNeitherLeaderNorParent() {
        let youth = scout(unitName: "Troop1001", leader: "Sam Smith")
        #expect(AdultLocator.locate(for: youth, among: [adult("Sam", "", unitName: "Troop1001")]).isEmpty)
    }

    // SPEC.md D-23, after the 2026-09-30 event: the cases Windows'
    // SchedulerLogicTests and Java's test-board-builder.js run too.

    /// Java's test-board-builder.js and Windows'
    /// ALeaderFromAnotherUnitIsFoundByFirstAndLastName, with their adults.
    @Test func aLeaderFromAnotherUnitIsFoundByFirstAndLastName() throws {
        let youth = scout(unitName: "Troop1001", leader: "Sam Smith")
        let found = try #require(AdultLocator.introduction(for: youth, among: [adult("Sam", "Smith", unitName: "Troop9")]))
        #expect(found.map(\.adult.fullName) == ["Sam Smith"])
        #expect(found.map(\.relation) == [.leader])
    }

    /// Java's test-board-builder.js and Windows' AnAdultWithNoNameIsNobodysLeader,
    /// which also looks for parents.
    @Test func anAdultWithNoNameIsNobodysLeader() throws {
        let youth = scout(unitName: "Troop1001", leader: "Sam Smith")
        let nameless = adult("", "", unitName: "Troop9")
        #expect(try #require(AdultLocator.introduction(for: youth, among: [nameless])).isEmpty)
        #expect(AdultLocator.locate(for: youth, among: [nameless]).isEmpty)
    }

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
        #expect(AdultLocator.introductionText(for: youth, among: [leader, parent])
            == "\n\nNo one has said they'll introduce them. Their leader:\nLee Leader (Main room)")

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

    /// Settings › Timers shows each limit at 0 as off, so turning Running
    /// long off leaves the overdue alarm on (as Windows' TimerFor does).
    @Test(arguments: [BoardType.finalBoard, .projectReview])
    func runningLongOffStillGoesOverdue(boardType: BoardType) {
        var noYellow = config
        noYellow.finalYellowMinutes = 0
        noYellow.finalRedMinutes = 45
        noYellow.projectYellowMinutes = 0
        noYellow.projectRedMinutes = 45
        #expect(RoomTimer.state(status: .inProgress, boardType: boardType, minutes: 44, config: noYellow) == .okay)
        #expect(RoomTimer.state(status: .inProgress, boardType: boardType, minutes: 45, config: noYellow) == .overdue)
    }

    @Test(arguments: [BoardType.finalBoard, .projectReview])
    func overdueOffStillRunsLongAndNeverGoesOverdue(boardType: BoardType) {
        var noRed = config
        noRed.finalRedMinutes = 0
        noRed.projectRedMinutes = 0
        let yellow = boardType == .finalBoard ? config.finalYellowMinutes : config.projectYellowMinutes
        #expect(RoomTimer.state(status: .inProgress, boardType: boardType, minutes: yellow - 1, config: noRed) == .okay)
        #expect(RoomTimer.state(status: .inProgress, boardType: boardType, minutes: yellow, config: noRed) == .warning)
        #expect(RoomTimer.state(status: .inProgress, boardType: boardType, minutes: 500, config: noRed) == .warning)
    }

    @Test(arguments: [BoardType.finalBoard, .projectReview])
    func aReviewWithBothLimitsOffIsNotTimed(boardType: BoardType) {
        var off = config
        off.finalYellowMinutes = 0
        off.finalRedMinutes = 0
        off.projectYellowMinutes = 0
        off.projectRedMinutes = 0
        #expect(RoomTimer.state(status: .inProgress, boardType: boardType, minutes: 500, config: off) == nil)
    }

    @Test func nothingElseIsTimed() {
        #expect(RoomTimer.state(status: .registered, boardType: .finalBoard, minutes: 500, config: config) == nil)
        #expect(RoomTimer.state(status: .completed, boardType: .finalBoard, minutes: 500, config: config) == nil)
        var off = config
        off.conveneRedMinutes = 0
        #expect(RoomTimer.state(status: .seated, boardType: .finalBoard, minutes: 500, config: off) == nil)
    }
}

/// A room turning running long or overdue is said once, as Windows'
/// UpdateRoomTimers says it, and opening an event reads out nothing.
@Suite("Room timers, read aloud")
struct RoomTimerSpeechTests {
    let config = Config.standard
    let clock = Date(timeIntervalSince1970: 1_790_118_300)

    private func board(_ first: String, room: String, _ status: BoardStatus, _ boardType: BoardType = .finalBoard,
                       minutesAgo: Int) -> Scout {
        var youth = scout(first, "Doe", boardType: boardType, status: status)
        youth.room = room
        youth.lastUpdateTime = Timestamp.recordStamp(for: clock.addingTimeInterval(TimeInterval(-minutesAgo * 60)))
        return youth
    }

    private func check(_ previous: RoomTimerSpeech.States?, _ youth: [Scout], minutesLater: Int = 0)
        -> (states: RoomTimerSpeech.States, spoken: String) {
        RoomTimerSpeech.check(previous: previous, youth: youth, config: config, now: clock.addingTimeInterval(TimeInterval(minutesLater * 60)))
    }

    @Test func theFirstCheckOnlyRecords() {
        let first = check(nil, [board("Jane", room: "101", .inProgress, minutesAgo: 50)])
        #expect(first.spoken.isEmpty, "a room already overdue when the event opens is not read out")
        #expect(first.states.values.contains(.overdue))
    }

    @Test func aRoomTurningIsSaidOnce() {
        let youth = [board("Jane", room: "101", .inProgress, minutesAgo: 29), board("Bill", room: "102", .seated, minutesAgo: 10)]
        let start = check(nil, youth)
        let long = check(start.states, youth, minutesLater: 2)
        #expect(long.spoken == "Room 101 is running long: Jane Doe, 31 minutes.")
        #expect(check(long.states, youth, minutesLater: 3).spoken.isEmpty, "still running long: not said again")
        let overdue = check(long.states, youth, minutesLater: 21)
        #expect(overdue.spoken == "Room 101 is overdue: Jane Doe, 50 minutes. Room 102 is overdue: Bill Doe, 31 minutes.",
                "every room that turned, in one announcement")
    }

    @Test func aBoardNotSeenBeforeCountsAsOnTime() {
        let start = check(nil, [])
        let late = check(start.states, [board("Ann", room: "200A", .inProgress, .projectReview, minutesAgo: 1)], minutesLater: 0)
        #expect(late.spoken.isEmpty)
        let undone = check(start.states, [board("Ann", room: "200A", .inProgress, .projectReview, minutesAgo: 41)])
        #expect(undone.spoken == "Room 200A is overdue: Ann Doe, 41 minutes.", "a board put back by Undo, already over")
    }

    @Test func oneMinuteIsSingular() {
        var quick = config
        quick.finalYellowMinutes = 1
        let youth = [board("Jane", room: "101", .inProgress, minutesAgo: 0)]
        let start = RoomTimerSpeech.check(previous: nil, youth: youth, config: quick, now: clock)
        let turned = RoomTimerSpeech.check(previous: start.states, youth: youth, config: quick, now: clock.addingTimeInterval(60))
        #expect(turned.spoken == "Room 101 is running long: Jane Doe, 1 minute.")
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

    /// SPEC.md D-1: a name the files read back with "~" for its comma is
    /// found, and said, as the screen shows it.
    @Test func aNameWithACommaIsFoundAsShown() {
        let junior = youth("Lysander", "Whitmore~ Jr.", .registered)
        let found = PersonFind.people("whitmore, jr", youth: [junior], adults: [])
        #expect(found.map(\.sentence) == ["Lysander Whitmore, Jr. is waiting."])
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

    /// VoiceOver hears whom the narrowed cards hold, which only the cards
    /// show, then the note (Windows' UpdatePersonFind).
    @Test func theFindSaysWhomTheRoomsHold() {
        let rooms = [room("101", .finalBoard, scoutName: "Arthur Eldred"), room("102", .finalBoard), room("200A", .projectReview)]
        func spoken(_ query: String, youth: [Scout]? = nil) -> String {
            let found = PersonFind.people(query, youth: youth ?? signedIn.youth, adults: signedIn.adults)
            return PersonFind.spoken(query, people: found, rooms: rooms)
        }
        #expect(spoken("").isEmpty && spoken("  ").isEmpty)
        #expect(spoken("armstrong") == "Neil Armstrong is in room 101.")
        #expect(spoken("ar") == "Arthur Eldred is in room 101. Neil Armstrong is in room 101. Charles Duke has gone home.")
        #expect(spoken("20") == "1 room by that name: 200A.")
        #expect(spoken("10") == "2 rooms by that name: 101, 102.")
        #expect(spoken("bill") == "Bill Amend is waiting.")
        #expect(spoken("Spielberg") == "No one by that name has signed in.")
        let crowd = (1...6).map { youth("Pat", "Seated\($0)", .inProgress, room: "10\($0)") }
        #expect(spoken("pat", youth: crowd) == "Pat Seated1 is in room 101. Pat Seated2 is in room 102. Pat Seated3 is in room 103. "
            + "Pat Seated4 is in room 104. And 2 more in rooms.")
    }
}
