import EagleBoardsCore
import Foundation
import Testing

/// The boards being drawn up for waiting youth (SPEC.md D-12, amended): a
/// proposal the operator has not changed follows the event, and one they
/// have changed is theirs. Adults sign in with `registerAdult`, as the
/// tablet does, and `refresh` runs where the scheduler would run it, when
/// `BoardDrafts.fingerprint` changes.
@MainActor
@Suite("Boards being drawn up")
struct BoardDraftTests {
    let scratch: ScratchFolder
    let event: BoardEvent
    /// Two youth waiting for a final board, A first in the queue.
    let youthA: Scout.ID
    let youthB: Scout.ID

    init() throws {
        scratch = try ScratchFolder()
        event = try BoardEvent(folder: scratch.dataFolder, date: "2026-10-24")
        try event.addRoom(named: "101", boardType: .finalBoard)
        try event.addRoom(named: "102", boardType: .finalBoard)
        try event.addRoom(named: "200A", boardType: .projectReview)
        youthA = try event.registerYouth([
            "Last": "Achterberg", "First": "Rowan", "Email": "rowan@example.org", "UnitType": "Troop", "Unit": "1001",
            "BoardType": "Final",
        ]).id
        youthB = try event.registerYouth([
            "Last": "Brannigan", "First": "Tobiah", "Email": "tobiah@example.org", "UnitType": "Troop", "Unit": "1002",
            "BoardType": "Final",
        ]).id
    }

    /// Sign an adult in at the tablet. Each has a unit of their own, none a
    /// youth's, so the same-unit rule stays out of these cases.
    @discardableResult
    private func signIn(_ last: String, _ first: String, unit: Int, final: BoardRole = .member) throws -> Adult.ID {
        try event.registerAdult([
            "Last": last, "First": first, "Email": "\(first.lowercased()).\(last.lowercased())@example.org",
            "UnitType": "Troop", "Unit": "\(unit)", "FinalBoard": final.rawValue, "ProjectReview": BoardRole.member.rawValue,
        ]).id
    }

    private func signInChairs(_ count: Int) throws -> [Adult.ID] {
        let names = [("Okonkwo", "Adaeze"), ("Lindqvist", "Soren"), ("Featherstone", "Imogen")]
        return try names.prefix(count).enumerated().map { index, name in
            try signIn(name.0, name.1, unit: 2001 + index, final: .chair)
        }
    }

    private func signInMembers(_ count: Int, from start: Int = 0) throws -> [Adult.ID] {
        let names = [
            ("Haverford", "Quillon"), ("Mbeki", "Thandiwe"), ("Castellanos", "Ines"), ("Yoshida", "Kenji"),
            ("Pellegrino", "Marisol"), ("Adebayo", "Femi"), ("Vasquez", "Lorna"),
        ]
        return try names[start..<(start + count)].enumerated().map { index, name in
            try signIn(name.0, name.1, unit: 2101 + start + index)
        }
    }

    private func youth(_ id: Scout.ID) throws -> Scout { try #require(event.scout(id: id)) }

    private func refresh(_ drafts: inout BoardDrafts, selected id: Scout.ID) throws {
        drafts.refresh(selected: try youth(id), in: event)
    }

    private func members(of draft: BoardDraft) -> [Adult] {
        draft.memberIDs.compactMap { event.adult(id: $0) }
    }

    /// The chairs Seat Board's sheet offers for this board.
    private func qualifiedChairs(on draft: BoardDraft, for id: Scout.ID) throws -> [Adult] {
        SeatingReview(scout: try youth(id), members: members(of: draft), room: draft.roomID.flatMap { event.room(id: $0) })
            .qualifiedChairs
    }

    // MARK: - A proposal follows the event

    @Test func anUntouchedBoardFillsAsAdultsArrive() throws {
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA]?.memberIDs == [])
        #expect(drafts[youthA]?.problems.isEmpty == false)

        let chair = try signInChairs(1)[0]
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA]?.memberIDs == [chair])

        let members = try signInMembers(2)
        try refresh(&drafts, selected: youthA)
        let draft = try #require(drafts[youthA])
        #expect(draft.memberIDs == [chair] + members || draft.memberIDs == [chair] + members.reversed())
        #expect(draft.chairID == chair)
        #expect(draft.roomID == "ROOM:101")
        #expect(draft.problems.isEmpty)
        #expect(!draft.isEdited)
    }

    @Test func aChosenRoomIsKeptAndTheBoardStillFills() throws {
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA]?.roomID == "ROOM:101")
        drafts.setRoom("ROOM:102", for: youthA)
        #expect(drafts[youthA]?.roomID == "ROOM:102")
        #expect(drafts[youthA]?.isEdited == false)

        _ = try signInChairs(1)
        _ = try signInMembers(2)
        try refresh(&drafts, selected: youthA)
        let draft = try #require(drafts[youthA])
        #expect(draft.roomID == "ROOM:102")
        #expect(draft.memberIDs.count == 3)
        #expect(!draft.isEdited)

        // Once the room is gone, the suggestion's room instead.
        try event.removeRoom(id: "ROOM:102")
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA]?.roomID == "ROOM:101")
    }

    @Test func aChosenRoomGivenToAnotherBoardFallsBackToTheSuggestionsRoom() throws {
        let chairs = try signInChairs(2)
        let members = try signInMembers(4)
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        drafts.setRoom("ROOM:102", for: youthA)
        let onA = try #require(drafts[youthA]).memberIDs

        let chairB = try #require(chairs.first { !onA.contains($0) })
        let membersB = members.filter { !onA.contains($0) }
        try event.seatBoard(roomID: "ROOM:102", scoutID: youthB, chairID: chairB, memberIDs: [chairB] + membersB)
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA]?.roomID == "ROOM:101")
        #expect(drafts[youthA]?.isEdited == false)
    }

    @Test func anUntouchedBoardKeepsItsRoomWhenAnEarlierRoomFrees() throws {
        let chairs = try signInChairs(2)
        let members = try signInMembers(4)
        try event.seatBoard(roomID: "ROOM:101", scoutID: youthB, chairID: chairs[1], memberIDs: [chairs[1]] + members[2...])
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA]?.roomID == "ROOM:102")

        try event.startReview(scoutID: youthB)
        try event.completeBoard(scoutID: youthB, result: .approved, notes: "")
        #expect(event.room(id: "ROOM:101")?.isFree == true)
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA]?.roomID == "ROOM:102")
        #expect(drafts[youthA]?.isEdited == false)
    }

    @Test func aRoomOfTheOtherKindIsKeptWithoutTheNoFreeRoomComplaint() throws {
        let chairs = try signInChairs(2)
        let members = try signInMembers(4)
        try event.seatBoard(roomID: "ROOM:101", scoutID: youthB, chairID: chairs[1], memberIDs: [chairs[1]] + members[2...])
        try event.removeRoom(id: "ROOM:102")
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        let noFreeRoom = BoardSuggestion.noFreeRoom(for: .finalBoard)
        #expect(drafts[youthA]?.roomID == nil)
        #expect(drafts[youthA]?.problems.contains(noFreeRoom) == true)

        drafts.setRoom("ROOM:200A", for: youthA)
        #expect(drafts[youthA]?.problems.contains(noFreeRoom) == false)
        #expect(drafts[youthA]?.isEdited == false)

        _ = try signInMembers(1, from: 4)
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA]?.roomID == "ROOM:200A")
        #expect(drafts[youthA]?.problems.contains(noFreeRoom) == false)
    }

    @Test func withProposalsOffAChosenRoomIsKeptAndTheBoardStaysEmpty() throws {
        _ = try signInChairs(1)
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event, proposing: false)
        #expect(drafts[youthA] == BoardDraft(roomID: "ROOM:101"))
        drafts.setRoom("ROOM:102", for: youthA)

        _ = try signInMembers(2)
        drafts.refresh(selected: try youth(youthA), in: event, proposing: false)
        #expect(drafts[youthA] == BoardDraft(roomID: "ROOM:102"))
    }

    @Test func aProposedAdultWhoGoesHomeOrIsSeatedElsewhereDropsOut() throws {
        let chairs = try signInChairs(3)
        let members = try signInMembers(6)
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        // Chair first, so the last is someone sitting as a member.
        let gone = try #require(drafts[youthA]?.memberIDs.last)

        try event.setAvailable(false, adultID: gone)
        try refresh(&drafts, selected: youthA)
        var draft = try #require(drafts[youthA])
        #expect(!draft.memberIDs.contains(gone))
        #expect(draft.memberIDs.count == 3)
        #expect(!draft.isEdited)

        let taken = try #require(draft.memberIDs.last)
        let chairB = try #require(chairs.first { !draft.memberIDs.contains($0) })
        let otherB = try #require(members.first { !draft.memberIDs.contains($0) && $0 != gone })
        try event.seatBoard(roomID: "ROOM:102", scoutID: youthB, chairID: chairB, memberIDs: [chairB, taken, otherB])
        try refresh(&drafts, selected: youthA)
        draft = try #require(drafts[youthA])
        #expect(!draft.memberIDs.contains(taken))
        #expect(draft.memberIDs.count == 3)
        #expect(!draft.isEdited)
    }

    // MARK: - The operator's board is kept

    @Test func anEditedBoardIsKept() throws {
        let chair = try signInChairs(1)[0]
        let member = try signInMembers(1)[0]
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA]?.memberIDs == [chair, member])
        drafts.remove([member], for: youthA)
        let edited = try #require(drafts[youthA])
        #expect(edited.isEdited)

        _ = try signInMembers(2, from: 1)
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA] == edited)
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA] == edited)
    }

    @Test func anotherYouthGetsTheirOwn() throws {
        _ = try signInChairs(2)
        _ = try signInMembers(4)
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        drafts.select(try youth(youthB), in: event)
        #expect(drafts[youthB]?.memberIDs.count == 3)
        #expect(drafts[youthB]?.isEdited == false)

        // An untouched proposal is not kept while the operator looks at
        // someone else; it is made afresh when they come back.
        try refresh(&drafts, selected: youthB)
        #expect(drafts[youthA] == nil)
        #expect(drafts[youthB] != nil)

        drafts.select(try youth(youthA), in: event)
        let member = try #require(drafts[youthA]?.memberIDs.last)
        drafts.remove([member], for: youthA)
        let edited = try #require(drafts[youthA])
        drafts.select(try youth(youthB), in: event)
        try refresh(&drafts, selected: youthB)
        #expect(drafts[youthA] == edited)
        #expect(drafts[youthB]?.isEdited == false)
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA] == edited)
    }

    enum Edit: CaseIterable, Sendable {
        case remove, add, fillTheRest, clear, makeChair
    }

    @Test(arguments: Edit.allCases)
    func eachChangeByHandMakesTheBoardTheOperators(_ edit: Edit) throws {
        // Three who may chair and one plain member: the proposal takes two
        // of the chairs and the member, so there is someone left to add and
        // a second chair on the board to hand the chair to.
        let chairs = try signInChairs(3)
        let member = try signInMembers(1)[0]
        var drafts = BoardDrafts()
        let youth = try self.youth(youthA)
        drafts.select(youth, in: event)
        let proposed = try #require(drafts[youthA])
        #expect(!proposed.isEdited)
        #expect(proposed.memberIDs.contains(member))
        #expect(proposed.memberIDs.filter { chairs.contains($0) }.count == 2)

        switch edit {
        case .remove:
            drafts.remove([member], for: youthA)
        case .add:
            drafts.add(chairs.filter { !proposed.memberIDs.contains($0) }, for: youthA, in: event)
            #expect(drafts[youthA]?.memberIDs.count == 4)
        case .fillTheRest:
            drafts.fill(for: youth, in: event)
        case .clear:
            drafts.clear(youthA)
            #expect(drafts[youthA]?.memberIDs == [])
            #expect(drafts[youthA]?.chairID == nil)
            #expect(drafts[youthA]?.roomID == proposed.roomID)
        case .makeChair:
            let otherID = try #require(proposed.memberIDs.first { chairs.contains($0) && $0 != proposed.chairID })
            drafts.makeChair(try #require(event.adult(id: otherID)), for: youth, in: event)
            #expect(drafts[youthA]?.chairID == otherID)
        }
        let edited = try #require(drafts[youthA])
        #expect(edited.isEdited)

        _ = try signInMembers(2, from: 1)
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA] == edited)
    }

    @Test func aFrozenBoardIsNotProposedAgainUntilItThaws() throws {
        let chair = try signInChairs(1)[0]
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA]?.memberIDs == [chair])

        // The Seat Board sheet is open on it.
        drafts.frozenID = youthA
        _ = try signInMembers(2)
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA]?.memberIDs == [chair])
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA]?.memberIDs == [chair])
        #expect(drafts[youthA]?.isEdited == false)

        // The sheet closed without seating: the board catches up.
        drafts.frozenID = nil
        try refresh(&drafts, selected: youthA)
        let draft = try #require(drafts[youthA])
        #expect(draft.memberIDs.count == 3)

        let chairID = try #require(draft.chairToSeat(from: try qualifiedChairs(on: draft, for: youthA)))
        #expect(chairID == chair)
        try event.seatBoard(
            roomID: try #require(draft.roomID), scoutID: youthA, chairID: chairID, memberIDs: draft.memberIDs)
        drafts.discard(youthA)
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA] == nil)
    }

    // MARK: - The board's chair

    @Test func theBoardsChairIsTheSuggestionsAndSeatBoardStartsWithIt() throws {
        let chairs = try signInChairs(3)
        let member = try signInMembers(1)[0]
        var drafts = BoardDrafts()
        let youth = try self.youth(youthA)
        drafts.select(youth, in: event)
        let draft = try #require(drafts[youthA])
        let suggestion = BoardSuggestion(
            for: youth, adults: event.adults, rooms: event.rooms, waiting: [try self.youth(youthB)],
            freeSince: BoardSuggestion.freeSinceTimes(adults: event.adults, scouts: event.scouts))
        #expect(draft.chairID == suggestion.chairID)
        #expect(draft.memberIDs.first == draft.chairID)
        let qualified = try qualifiedChairs(on: draft, for: youthA)
        #expect(qualified.count == 2)
        #expect(draft.chairToSeat(from: qualified) == draft.chairID)

        // Make Chair is for someone on the board who may chair it and is
        // not its chair already.
        let memberAdult = try #require(event.adult(id: member))
        let offBoardID = try #require(chairs.first { !draft.memberIDs.contains($0) })
        let offBoard = try #require(event.adult(id: offBoardID))
        let currentID = try #require(draft.chairID)
        let current = try #require(event.adult(id: currentID))
        for adult in [memberAdult, offBoard, current] {
            #expect(!drafts.canMakeChair(adult, for: youth, in: event))
            drafts.makeChair(adult, for: youth, in: event)
        }
        #expect(drafts[youthA] == draft)

        let other = try #require(qualified.first { $0.id != draft.chairID })
        #expect(drafts.canMakeChair(other, for: youth, in: event))
        drafts.makeChair(other, for: youth, in: event)
        #expect(drafts[youthA]?.chairToSeat(from: qualified) == other.id)

        // Taking the chair off clears it. The first who may chair is then
        // the chair the inspector marks and Seat Board starts with, so Make
        // Chair has nothing to do for them.
        drafts.remove([other.id], for: youthA)
        let without = try #require(drafts[youthA])
        #expect(without.chairID == nil)
        let left = try qualifiedChairs(on: without, for: youthA)
        #expect(left.map(\.id) == [current.id])
        #expect(without.chairToSeat(from: left) == current.id)
        #expect(without.chair(among: members(of: without), for: .finalBoard) == current.id)
        #expect(!drafts.canMakeChair(current, for: youth, in: event))
    }

    @Test func aBoardDrawnUpByHandIsChairedByTheFirstWhoMay() throws {
        let chairs = try signInChairs(2)
        let member = try signInMembers(1)[0]
        var drafts = BoardDrafts()
        let youth = try self.youth(youthA)
        drafts.select(youth, in: event)
        drafts.clear(youthA)
        drafts.add([member] + chairs, for: youthA, in: event)
        var draft = try #require(drafts[youthA])
        #expect(draft.chairID == nil)
        #expect(draft.chair(among: members(of: draft), for: .finalBoard) == chairs[0])
        #expect(draft.chairToSeat(from: try qualifiedChairs(on: draft, for: youthA)) == chairs[0])

        let first = try #require(event.adult(id: chairs[0]))
        let second = try #require(event.adult(id: chairs[1]))
        #expect(!drafts.canMakeChair(first, for: youth, in: event))
        #expect(drafts.canMakeChair(second, for: youth, in: event))
        drafts.makeChair(second, for: youth, in: event)
        draft = try #require(drafts[youthA])
        #expect(draft.chairID == chairs[1])
        #expect(draft.chair(among: members(of: draft), for: .finalBoard) == chairs[1])
        #expect(draft.chairToSeat(from: try qualifiedChairs(on: draft, for: youthA)) == chairs[1])
    }

    @Test func fillTheRestSetsTheChair() throws {
        let chairs = try signInChairs(2)
        let members = try signInMembers(3)
        var drafts = BoardDrafts()
        let youth = try self.youth(youthA)
        drafts.select(youth, in: event)

        // No pick may chair it: Fill the Rest adds the chair.
        drafts.clear(youthA)
        drafts.add([members[0]], for: youthA, in: event)
        drafts.fill(for: youth, in: event)
        var draft = try #require(drafts[youthA])
        let added = try #require(draft.chairID)
        #expect(chairs.contains(added))
        #expect(draft.memberIDs.first == added)
        #expect(draft.memberIDs.count == 3)

        // A pick may chair it: they chair it.
        drafts.clear(youthA)
        drafts.add([members[0], chairs[1]], for: youthA, in: event)
        drafts.fill(for: youth, in: event)
        draft = try #require(drafts[youthA])
        #expect(draft.chairID == chairs[1])
        #expect(Array(draft.memberIDs.prefix(2)) == [members[0], chairs[1]])
    }

    @Test func anAdultTakenOffEveryBoardTakesTheChairWithThem() throws {
        let chair = try signInChairs(1)[0]
        let members = try signInMembers(2)
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA]?.chairID == chair)

        drafts.takeOff([chair])
        #expect(drafts[youthA]?.chairID == nil)
        #expect(drafts[youthA].map { Set($0.memberIDs) } == Set(members))
        #expect(drafts[youthA]?.isEdited == false)
    }

    // MARK: - What a proposal is made from

    @Test func linkingAnAdultOrChangingAUnitChangesTheFingerprint() throws {
        let chair = try signInChairs(1)[0]
        let members = try signInMembers(2)
        let adultID = members[0]
        var drafts = BoardDrafts()
        drafts.select(try youth(youthA), in: event)
        #expect(drafts[youthA].map { Set($0.memberIDs) } == Set([chair] + members))
        let start = BoardDrafts.fingerprint(of: event)

        try event.setSupporting(true, adultID: adultID, scoutID: youthA)
        let linked = BoardDrafts.fingerprint(of: event)
        #expect(linked != start)

        // Moved into youth A's unit: the change the scheduler sees is the
        // one that takes them off A's untouched proposal.
        var adult = try #require(event.adult(id: adultID))
        adult.unit = "1001"
        try event.updateAdult(adult)
        let adultMoved = BoardDrafts.fingerprint(of: event)
        #expect(adultMoved != linked)
        try refresh(&drafts, selected: youthA)
        #expect(drafts[youthA]?.memberIDs.contains(adultID) == false)
        #expect(drafts[youthA]?.isEdited == false)

        adult = try #require(event.adult(id: adultID))
        adult.woodBadge = "Y"
        try event.updateAdult(adult)
        let woodBadge = BoardDrafts.fingerprint(of: event)
        #expect(woodBadge != adultMoved)

        var youth = try self.youth(youthB)
        youth.unit = "1003"
        try event.updateYouth(youth)
        #expect(BoardDrafts.fingerprint(of: event) != woodBadge)
    }
}
