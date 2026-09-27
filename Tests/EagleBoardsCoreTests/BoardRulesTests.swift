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

/// The suggestion weighing the whole waiting line. The same cases, in the
/// same order, are in the Java version's scripts/test-seat-conflicts.js and
/// the Windows version's SchedulerLogicTests; keep all three in step.
/// Arguments are in the Java test's order: final role, then project.
@Suite("Board suggestion across the waiting line")
struct WaitingLineSuggestionTests {
    private func pool(_ id: String, _ unit: String, _ final: String, _ project: String, room: String = "") -> Adult {
        Adult(fields: [
            "Type": "ADULT", "ID": id, "First": id, "Last": id, "UnitName": unit,
            "FinalBoard": final, "ProjectReview": project, "Room": room,
        ])
    }

    private func queue(_ id: String, _ unit: String, _ boardType: BoardType) -> Scout {
        Scout(fields: [
            "Type": "SCOUT", "ID": id, "First": id, "Last": id, "UnitName": unit,
            "BoardType": boardType.rawValue, "Status": BoardStatus.registered.rawValue,
        ])
    }

    private func propose(_ youth: Scout, _ adults: [Adult], waiting: [Scout] = []) -> BoardSuggestion {
        BoardSuggestion(for: youth, adults: adults, rooms: [room("1", youth.boardType ?? .finalBoard)], waiting: waiting)
    }

    @Test func memberOnlyAdultsFillTheMemberSeatsNotAProjectChair() {
        let pick = propose(queue("S", "Troop1001", .finalBoard), [
            pool("FC", "Troop9001", "Chair", "Member"),
            pool("PC", "Troop9002", "Member", "Chair"),
            pool("M1", "Troop9003", "Member", "Member"),
            pool("M2", "Troop9004", "Member", "Member"),
        ])
        #expect(pick.memberIDs == ["FC", "M1", "M2"])
        #expect(pick.problems.isEmpty)
    }

    @Test func aChairOfOneKindIsUsedBeforeAChairOfBoth() {
        let pick = propose(queue("S", "Troop1001", .finalBoard), [
            pool("BOTH", "Troop9001", "Chair", "Chair"),
            pool("FC", "Troop9002", "Chair", "Member"),
            pool("M1", "Troop9003", "Member", "Member"),
            pool("M2", "Troop9004", "Member", "Member"),
        ])
        #expect(pick.chairID == "FC")
    }

    @Test func whenMemberOnlyAdultsRunOutAChairCapableAdultFillsTheSeat() {
        let pick = propose(queue("S", "Troop1001", .finalBoard), [
            pool("FC", "Troop9001", "Chair", "Member"),
            pool("PC", "Troop9002", "Member", "Chair"),
            pool("M1", "Troop9003", "Member", "Member"),
        ])
        #expect(pick.memberIDs == ["FC", "M1", "PC"])
        #expect(pick.problems.isEmpty)
    }

    @Test func anAdultWhoCannotServeTheNextYouthsTroopIsUsedHere() {
        let pick = propose(queue("S", "Troop1001", .projectReview), [
            pool("P1", "Troop3001", "Member", "Chair"),
            pool("P2", "Troop3002", "Member", "Chair"),
            pool("B", "Troop4001", "Member", "Member"),
            pool("A", "Troop2001", "Member", "Member"),
        ], waiting: [queue("T", "Troop2001", .projectReview)])
        #expect(pick.memberIDs == ["P1", "A"])
    }

    @Test func aYouthStillWaitingWhoCanBeSeatedOutranksAChairKeptForLater() {
        let pick = propose(queue("S", "Troop1001", .finalBoard), [
            pool("FC1", "Troop3001", "Chair", "Member"),
            pool("FC2", "Troop3002", "Chair", "Member"),
            pool("M", "Troop3003", "Member", "Member"),
            pool("Y", "Troop2001", "Member", "Chair"),
            pool("Z", "Troop2001", "Member", "Member"),
            pool("W", "Troop3004", "Member", "Member"),
        ], waiting: [queue("T", "Troop2001", .finalBoard)])
        #expect(pick.memberIDs == ["FC1", "Z", "Y"])
    }

    @Test func neverProposesSomeoneWhoCannotSit() {
        let pick = propose(queue("S", "Troop1001", .finalBoard), [
            pool("SAME", "Troop1001", "Chair", "Chair"),
            pool("BUSY", "Troop9001", "Chair", "Chair", room: "101"),
            pool("GONE", "Troop9002", "Chair", "Chair", room: disabledForTonightMarker),
            pool("NOPE", "Troop9003", "Unavailable", "Member"),
            pool("FC", "Troop9004", "Chair", "Member"),
            pool("M1", "Troop9005", "Member", "Member"),
            pool("M2", "Troop9006", "Member", "Member"),
        ])
        #expect(pick.memberIDs == ["FC", "M1", "M2"])
    }

    @Test func withNoChairItStillProposesTheMembersAndSaysSo() {
        let pick = propose(queue("S", "Troop1001", .finalBoard), [
            pool("M1", "Troop9001", "Member", "Member"),
            pool("M2", "Troop9002", "Member", "Member"),
        ])
        #expect(pick.chairID == nil)
        #expect(pick.memberIDs == ["M1", "M2"])
        #expect(pick.problems == ["No Final Board chairs are available."])
    }

    @Test func withTooFewMembersItProposesWhatThereIsAndSaysSo() {
        let pick = propose(queue("S", "Troop1001", .finalBoard), [
            pool("FC", "Troop9001", "Chair", "Member"),
            pool("M1", "Troop9002", "Member", "Member"),
        ])
        #expect(pick.memberIDs == ["FC", "M1"])
        #expect(pick.problems == ["Only 1 Final Board member is available."])
    }

    /// The event test's shape: 9 Final and 5 Project youth, 30 adults, five
    /// of whom chair anything. Proposing boards down the queue must reach the
    /// chair cap of five at once; sign-in order stalled at three, because the
    /// first Final board took both project chairs as its members.
    @Test func aWholeEventSeatsFiveBoardsAtOnce() {
        var adults = [
            pool("FC1", "Troop2001", "Chair", "Chair"),
            pool("FC2", "Troop2002", "Chair", "Member"),
            pool("FC3", "Troop2003", "Chair", "Member"),
            pool("PC1", "Troop2004", "Member", "Chair"),
            pool("PC2", "Troop2005", "Member", "Chair"),
        ]
        for number in 6...25 {
            adults.append(pool("M\(number)", "Troop\(2000 + number)", "Member", "Member"))
        }
        adults.append(pool("U26", "Troop2026", "Member", "Unavailable"))
        adults.append(pool("U27", "Troop2027", "Member", "Unavailable"))
        adults.append(pool("U28", "Troop1001", "Unavailable", "Member"))
        adults.append(pool("U29", "Troop1002", "Unavailable", "Member"))
        adults.append(pool("U30", "Troop1003", "Unavailable", "Member"))

        let line = (1...14).map { queue("S\($0)", "Troop\(1000 + $0)", $0 <= 9 ? .finalBoard : .projectReview) }
        var seated = Set<String>()
        var boards: [BoardType: Int] = [.finalBoard: 0, .projectReview: 0]
        for (index, youth) in line.enumerated() {
            let stillWaiting = line.filter { $0.id != youth.id && !seated.contains($0.id) }
            let pick = propose(youth, adults, waiting: stillWaiting)
            guard pick.problems.isEmpty, let boardType = youth.boardType else { continue }
            seated.insert(youth.id)
            boards[boardType, default: 0] += 1
            for adultIndex in adults.indices where pick.memberIDs.contains(adults[adultIndex].id) {
                adults[adultIndex].room = "R\(index)"
            }
        }
        #expect(boards[.finalBoard] == 3 && boards[.projectReview] == 2, "three Final and two Project at once")
    }

    // MARK: The adults who have waited longest to volunteer go first.

    private func signedIn(_ id: String, at time: String) -> Adult {
        Adult(fields: ["Type": "ADULT", "ID": id, "RegTime": time])
    }

    private func board(_ status: BoardStatus, _ memberIDs: String, finished: String) -> Scout {
        Scout(fields: ["Type": "SCOUT", "ID": "SCOUT:\(finished)", "Status": status.rawValue,
                       "BoardMembersIDs": memberIDs, "LastUpdateTime": finished])
    }

    @Test func freeSinceIsSignInOrWhenTheirLastBoardCompleted() {
        let since = BoardSuggestion.freeSinceTimes(adults: [
            signedIn("ADULT:Able:Ann:1", at: "2026-09-24_19:00-0400"),
            signedIn("ADULT:Baker:Bo:2", at: "2026-09-24_19:10-0400"),
            signedIn("ADULT:Cole:Cy:3", at: "2026-09-24_19:05-0400"),
            signedIn("ADULT:Whitmore~ Jr.:Lysander:4", at: "2026-09-24_19:00-0400"),
            signedIn("ADULT:Lee:Al:1", at: "2026-09-24_19:00-0400"),
        ], scouts: [
            board(.completed, "ADULT:Able:Ann:1,ADULT:Other:Oz:9", finished: "2026-09-24_19:40-0400"),
            // As it reads back after a restart: the files store the commas as '~'.
            board(.completed, "ADULT:X:X:9~ADULT:Whitmore~ Jr.:Lysander:4~ADULT:Lee:Al:12", finished: "2026-09-24_19:50-0400"),
            board(.registered, "", finished: "2026-09-24_20:00-0400"),  // a reset board
            board(.seated, "ADULT:Cole:Cy:3", finished: "2026-09-24_20:05-0400"),
        ])
        #expect(since["ADULT:Able:Ann:1"] == "2026-09-24_19:40-0400", "came off a completed board")
        #expect(since["ADULT:Baker:Bo:2"] == "2026-09-24_19:10-0400", "has not sat")
        #expect(since["ADULT:Cole:Cy:3"] == "2026-09-24_19:05-0400", "a running board does not count")
        #expect(since["ADULT:Whitmore~ Jr.:Lysander:4"] == "2026-09-24_19:50-0400", "a comma name after a restart")
        #expect(since["ADULT:Lee:Al:1"] == "2026-09-24_19:00-0400", "not mistaken for ADULT:Lee:Al:12")
    }

    @Test func amongEqualsThoseWhoHaveWaitedLongestAreProposed() {
        let youth = queue("S", "Troop1001", .finalBoard)
        let adults = [
            pool("FC", "Troop9001", "Chair", "Member"), pool("M1", "Troop9002", "Member", "Member"),
            pool("M2", "Troop9003", "Member", "Member"), pool("M3", "Troop9004", "Member", "Member"),
        ]
        let since = ["FC": "2026-09-24_19:00-0400", "M1": "2026-09-24_19:40-0400",
                     "M2": "2026-09-24_19:10-0400", "M3": "2026-09-24_19:20-0400"]
        let pick = BoardSuggestion(for: youth, adults: adults, rooms: [room("1", .finalBoard)], freeSince: since)
        #expect(pick.memberIDs == ["FC", "M2", "M3"])
    }

    @Test func waitingLongestDoesNotOutrankKeepingAChairFree() {
        let youth = queue("S", "Troop1001", .finalBoard)
        let adults = [
            pool("FC", "Troop9001", "Chair", "Member"), pool("PC", "Troop9002", "Member", "Chair"),
            pool("M1", "Troop9003", "Member", "Member"), pool("M2", "Troop9004", "Member", "Member"),
        ]
        let since = ["FC": "2026-09-24_19:00-0400", "PC": "2026-09-24_18:30-0400",
                     "M1": "2026-09-24_19:30-0400", "M2": "2026-09-24_19:35-0400"]
        let pick = BoardSuggestion(for: youth, adults: adults, rooms: [room("1", .finalBoard)], freeSince: since)
        #expect(pick.memberIDs == ["FC", "M1", "M2"])
    }

    // MARK: Volunteers who came for any board go before a youth's own leaders.

    private func linked(_ adult: Adult, supporting: String, woodBadge: String = "") -> Adult {
        var adult = adult
        adult.supporting = supporting
        adult.woodBadge = woodBadge
        return adult
    }

    @Test func anUnattachedVolunteerIsProposedBeforeAYouthsLeaderWhoHasWaitedLonger() {
        let adults = [
            pool("FC", "Troop9001", "Chair", "Member"),
            linked(pool("LEAD", "Troop9002", "Member", "Member"), supporting: "SCOUT:Other:Oli:3001"),
            pool("V1", "Troop9003", "Member", "Member"), pool("V2", "Troop9004", "Member", "Member"),
        ]
        let since = ["LEAD": "2026-09-24_18:00-0400", "V1": "2026-09-24_19:30-0400", "V2": "2026-09-24_19:40-0400"]
        let pick = BoardSuggestion(for: queue("S", "Troop1001", .finalBoard), adults: adults,
                                   rooms: [room("1", .finalBoard)], freeSince: since)
        #expect(pick.memberIDs == ["FC", "V1", "V2"])
    }

    @Test func aWoodBadgeVolunteerCountsAsHereForAnyBoard() {
        let adults = [
            pool("FC", "Troop9001", "Chair", "Member"),
            linked(pool("LEAD", "Troop9002", "Member", "Member"), supporting: "SCOUT:Other:Oli:3001"),
            linked(pool("WB", "Troop9003", "Member", "Member"), supporting: "SCOUT:Other:Oli:3001", woodBadge: "Y"),
            pool("V", "Troop9004", "Member", "Member"),
        ]
        let since = ["LEAD": "2026-09-24_18:00-0400", "WB": "2026-09-24_19:00-0400", "V": "2026-09-24_19:30-0400"]
        let pick = BoardSuggestion(for: queue("S", "Troop1001", .finalBoard), adults: adults,
                                   rooms: [room("1", .finalBoard)], freeSince: since)
        #expect(pick.memberIDs == ["FC", "WB", "V"])
    }

    @Test func comingForAnyBoardDoesNotOutrankKeepingAChairFree() {
        let adults = [
            pool("FC", "Troop9001", "Chair", "Member"),
            pool("PC", "Troop9002", "Member", "Chair"),
            linked(pool("L1", "Troop9003", "Member", "Member"), supporting: "SCOUT:A:A:1"),
            linked(pool("L2", "Troop9004", "Member", "Member"), supporting: "SCOUT:B:B:2"),
        ]
        let pick = propose(queue("S", "Troop1001", .finalBoard), adults)
        #expect(pick.memberIDs == ["FC", "L1", "L2"])
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

/// Link and Unlink editing a Supporting list. The same cases
/// are in the Java and Windows versions.
@Suite("Linking an adult to a youth")
struct SupportLinkTests {
    @Test(arguments: [
        ("", "SCOUT:A:A:1", true, "SCOUT:A:A:1"),
        ("SCOUT:A:A:1", "SCOUT:B:B:2", true, "SCOUT:A:A:1|SCOUT:B:B:2"),
        ("SCOUT:A:A:1|SCOUT:B:B:2", "SCOUT:A:A:1", true, "SCOUT:B:B:2|SCOUT:A:A:1"),
        ("SCOUT:A:A:1|SCOUT:B:B:2", "SCOUT:A:A:1", false, "SCOUT:B:B:2"),
        ("SCOUT:A:A:1", "SCOUT:A:A:1", false, ""),
        ("SCOUT:Doe~ Jr.:Jan:1", "SCOUT:B:B:2", true, "SCOUT:Doe~ Jr.:Jan:1|SCOUT:B:B:2"),
    ])
    func linkingEditsTheSupportingList(supporting: String, scoutID: String, linked: Bool, expected: String) {
        #expect(Adult.withSupportLink(supporting, scoutID, linked: linked) == expected)
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
        #expect(!adult("Gone", "Home", unitName: "Troop1", room: disabledForTonightMarker).canJoin(.finalBoard))
    }
}
