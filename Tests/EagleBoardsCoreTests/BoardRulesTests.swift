import EagleBoardsCore
import Testing

// The composition rules as pure functions. These carry over every case from
// the Java project's scripts/test-seat-conflicts.js, then cover the pieces the
// Mac app adds: the one-pass seating review, the board suggestion, locating
// leaders and parents, and the room timers.

private func adult(
    _ first: String, _ last: String, unitName: String,
    final finalRole: BoardRole = .member, project projectRole: BoardRole = .member, room: String = ""
) -> Adult {
    Adult(fields: [
        "Type": "ADULT", "ID": "ADULT:\(last):\(first)", "First": first, "Last": last,
        "UnitName": unitName, "FinalBoard": finalRole.rawValue, "ProjectReview": projectRole.rawValue, "Room": room,
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

@Suite("Same-unit board members")
struct UnitConflictTests {
    @Test func adultInTheScoutsUnitIsFlagged() {
        #expect(names(BoardRules.unitConflicts(scoutUnitName: "Troop1234", members: [adult("Robin", "Sameunit", unitName: "Troop1234")])) == ["Robin Sameunit"])
    }

    @Test func boardWithNoOverlapIsClean() {
        let members = [
            adult("Jordan", "Otherunit", unitName: "Troop5678"),
            adult("Casey", "Otherunit", unitName: "Troop9999"),
            adult("Sam", "Otherunit", unitName: "Pack0042"),
        ]
        #expect(BoardRules.unitConflicts(scoutUnitName: "Troop1234", members: members).isEmpty)
    }

    @Test func everySameUnitMemberIsReportedNotJustTheFirst() {
        let members = [
            adult("Robin", "Sameunit", unitName: "Troop1234"),
            adult("Alex", "Sameunit", unitName: "Troop1234"),
            adult("Jordan", "Otherunit", unitName: "Troop5678"),
        ]
        #expect(names(BoardRules.unitConflicts(scoutUnitName: "Troop1234", members: members)) == ["Robin Sameunit", "Alex Sameunit"])
    }

    @Test func onlyTheOverlappingMembersAreReturned() {
        let members = [
            adult("Jordan", "Otherunit", unitName: "Troop5678"),
            adult("Robin", "Sameunit", unitName: "Troop1234"),
            adult("Casey", "Otherunit", unitName: "Troop9999"),
        ]
        #expect(names(BoardRules.unitConflicts(scoutUnitName: "Troop1234", members: members)) == ["Robin Sameunit"])
    }

    @Test func anEntireSameUnitBoardIsFullyReported() {
        let members = ["Robin", "Alex", "Jordan"].map { adult($0, "Sameunit", unitName: "Troop1234") }
        #expect(names(BoardRules.unitConflicts(scoutUnitName: "Troop1234", members: members)) == ["Robin Sameunit", "Alex Sameunit", "Jordan Sameunit"])
    }

    @Test(arguments: [
        ("Troop12", "Troop123"),     // a unit that is a prefix of another
        ("Troop1234", "Pack1234"),   // same number, different unit type
        ("", ""),                    // blank does not match blank
        ("Troop1234", ""),           // known scout unit, blank member unit
        ("", "Troop5678"),           // blank scout unit, known member unit
        ("Troop1234", "TROOP1234"),  // case differs: not the same stored unit
    ])
    func unitNameEdgeCasesAreNotMatches(scoutUnit: String, memberUnit: String) {
        #expect(BoardRules.unitConflicts(scoutUnitName: scoutUnit, members: [adult("Robin", "Member", unitName: memberUnit)]).isEmpty)
    }

    @Test func noMembersYieldsNoConflicts() {
        #expect(BoardRules.unitConflicts(scoutUnitName: "Troop1234", members: []).isEmpty)
    }
}

@Suite("National floor: one member from outside the unit")
struct OutsideMemberTests {
    @Test func aBoardEntirelyFromTheScoutsUnitHasNoOutsideMember() {
        let members = ["Robin", "Alex", "Jordan"].map { adult($0, "Sameunit", unitName: "Troop1234") }
        #expect(!BoardRules.hasMemberFromOutsideUnit(scoutUnitName: "Troop1234", members: members))
    }

    @Test func oneOutsideMemberIsEnough() {
        let members = [
            adult("Robin", "Sameunit", unitName: "Troop1234"),
            adult("Alex", "Sameunit", unitName: "Troop1234"),
            adult("Jordan", "Otherunit", unitName: "Troop5678"),
        ]
        #expect(BoardRules.hasMemberFromOutsideUnit(scoutUnitName: "Troop1234", members: members))
    }

    @Test func aFullyCrossUnitBoardMeetsTheFloor() {
        let members = [adult("Jordan", "Otherunit", unitName: "Troop5678"), adult("Casey", "Otherunit", unitName: "Troop9999")]
        #expect(BoardRules.hasMemberFromOutsideUnit(scoutUnitName: "Troop1234", members: members))
    }

    @Test func aBlankMemberUnitCountsAsOutside() {
        let members = [adult("Robin", "Sameunit", unitName: "Troop1234"), adult("Pat", "Nounit", unitName: "")]
        #expect(BoardRules.hasMemberFromOutsideUnit(scoutUnitName: "Troop1234", members: members))
    }

    @Test func anUnknownScoutUnitNeverBlocks() {
        #expect(BoardRules.hasMemberFromOutsideUnit(scoutUnitName: "", members: [adult("Robin", "Sameunit", unitName: "Troop1234")]))
    }

    @Test func sameNumberDifferentTypeCountsAsOutside() {
        #expect(BoardRules.hasMemberFromOutsideUnit(scoutUnitName: "Troop1234", members: [adult("Robin", "Otherunit", unitName: "Pack1234")]))
    }
}

@Suite("Board size")
struct BoardSizeTests {
    @Test(arguments: [
        (0, BoardRules.SizeVerdict.tooFew), (1, .tooFew), (2, .tooFew),
        (3, .ok), (4, .overPreferred), (5, .overPreferred), (6, .overPreferred),
        (7, .tooMany), (20, .tooMany),
    ])
    func boardOfReviewIsThreeToSix(count: Int, verdict: BoardRules.SizeVerdict) {
        #expect(BoardRules.checkBoardSize(count) == verdict)
        #expect(BoardRules.checkSize(count, for: .finalBoard) == verdict)
    }

    @Test(arguments: [
        (0, BoardRules.SizeVerdict.tooFew), (1, .tooFew),
        (2, .ok), (3, .overPreferred), (6, .overPreferred),
        (7, .tooMany), (20, .tooMany),
    ])
    func projectReviewIsTwoToSix(count: Int, verdict: BoardRules.SizeVerdict) {
        #expect(BoardRules.checkProjectSize(count) == verdict)
        #expect(BoardRules.checkSize(count, for: .projectReview) == verdict)
    }

    @Test func threeAndTwoMeanDifferentThingsForEachKind() {
        #expect([BoardRules.checkBoardSize(3), BoardRules.checkProjectSize(3)] == [.ok, .overPreferred])
        #expect([BoardRules.checkBoardSize(2), BoardRules.checkProjectSize(2)] == [.tooFew, .ok])
    }
}

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
        let gone = adult("Gone", "Home", unitName: "Troop2", room: disabledForTonightMarker)
        let busy = adult("Busy", "Elsewhere", unitName: "Troop3", room: "102")
        let unavailable = adult("Not", "Tonight", unitName: "Troop4", final: .unavailable)
        let review = SeatingReview(scout: scout(), members: [chair, gone, busy, unavailable], room: finalRoom)
        #expect(review.blockingProblems.contains { $0.contains("disabled for tonight") })
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
            adult("Gone", "Home", unitName: "Troop8", room: disabledForTonightMarker),
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

    @Test func aProjectReviewNeedsOneMemberBesideTheChair() {
        let adults = [
            adult("Pat", "Chair", unitName: "Troop1", project: .chair),
            adult("Morgan", "Member", unitName: "Troop2"),
            adult("Taylor", "Member", unitName: "Troop3"),
        ]
        let suggestion = BoardSuggestion(for: scout(boardType: .projectReview), adults: adults, rooms: [room("200A", .projectReview)])
        #expect(suggestion.memberIDs == ["ADULT:Chair:Pat", "ADULT:Member:Morgan"])
    }

    @Test func aSpareChairFillsInForAMissingMember() {
        let adults = [
            adult("Chris", "Chair", unitName: "Troop1", final: .chair),
            adult("Dana", "Chair", unitName: "Troop2", final: .chair),
            adult("Morgan", "Member", unitName: "Troop3"),
        ]
        let suggestion = BoardSuggestion(for: scout(), adults: adults, rooms: [room("101", .finalBoard)])
        #expect(suggestion.memberIDs == ["ADULT:Chair:Chris", "ADULT:Member:Morgan", "ADULT:Chair:Dana"])
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
