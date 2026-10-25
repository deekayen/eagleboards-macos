import Foundation

/// A board being drawn up for a waiting youth: proposed when they are
/// selected, then changed by hand in the inspector (SPEC.md D-10).
public struct BoardDraft: Sendable, Equatable {
    public var roomID: Room.ID?
    /// Who chairs it: the suggestion's or Fill the Rest's chair, or the
    /// member the operator made chair. Nil once that member is taken off, and
    /// on a board drawn up by hand; `chair(among:for:)` then falls back to
    /// the first member who may chair it.
    public var chairID: Adult.ID?
    /// Chair first when the suggestion made it, then in the order added.
    public var memberIDs: [Adult.ID]
    /// Why the suggestion could not propose a whole board.
    public var problems: [String]
    /// Changed by hand. A hand-made board is the operator's work and is
    /// kept while they look at other youth; a proposal is made afresh.
    public var isEdited: Bool

    public init(
        roomID: Room.ID? = nil, chairID: Adult.ID? = nil, memberIDs: [Adult.ID] = [], problems: [String] = [],
        isEdited: Bool = false
    ) {
        self.roomID = roomID
        self.chairID = chairID
        self.memberIDs = memberIDs
        self.problems = problems
        self.isEdited = isEdited
    }

    /// The chair Seat Board starts with: this board's chair while they may
    /// chair it, or else the first of `qualifiedChairs` (`SeatingReview`'s).
    public func chairToSeat(from qualifiedChairs: [Adult]) -> Adult.ID? {
        qualifiedChairs.first { $0.id == chairID }?.id ?? qualifiedChairs.first?.id
    }

    /// Who chairs the board as it stands, given its `members` in board
    /// order: the one the inspector marks Chair (SPEC.md D-10), and the one
    /// Seat Board starts with.
    public func chair(among members: [Adult], for boardType: BoardType) -> Adult.ID? {
        chairToSeat(from: members.filter { $0.canChair(boardType) })
    }

    /// A board in a room of the other kind has a room, so the suggestion's
    /// complaint that none of the youth's kind is free does not describe it.
    fileprivate mutating func dropNoFreeRoomProblems() {
        let noFreeRoom = BoardType.allCases.map(BoardSuggestion.noFreeRoom(for:))
        problems.removeAll { noFreeRoom.contains($0) }
    }
}

/// The boards being drawn up for the waiting youth, one per youth, until
/// Seat Board (SPEC.md D-12).
///
/// A board the app proposed and the operator has not changed follows the
/// event: whenever what it is made from changes (`fingerprint(of:)`),
/// `refresh` proposes it again, in the room it had while that room is still
/// free. Choosing a room does not change who sits on it, so it stays a
/// proposal. Removing, adding, Fill the Rest, Clear, and Make Chair make the
/// board the operator's, kept while they look at other youth, until
/// `suggest` or Seat Board. The Java version keeps the same rule with
/// `boardBuilder.untouched()`, and the Windows version with
/// `ProposedBoard.IsUntouched`.
public struct BoardDrafts: Sendable, Equatable {
    private var byYouth: [Scout.ID: BoardDraft] = [:]

    /// The youth whose board a refresh leaves as it is: the one in the open
    /// Seat Board sheet, so the members the operator is checking are the
    /// ones they seat, whoever signs in meanwhile.
    public var frozenID: Scout.ID?

    public init() {}

    public subscript(scoutID: Scout.ID) -> BoardDraft? { byYouth[scoutID] }

    /// Is this youth's board left alone by a refresh and by selecting them?
    private func isKept(_ scoutID: Scout.ID) -> Bool {
        guard let draft = byYouth[scoutID] else { return false }
        return draft.isEdited || scoutID == frozenID
    }

    // MARK: - Proposing

    /// A youth was selected. One who is waiting gets a proposal, unless their
    /// board is already the operator's; for anyone else nothing is drawn up.
    /// `proposing` false (Settings › General) proposes an empty board in a
    /// free room of the right kind, for the operator to pick.
    @MainActor
    public mutating func select(_ youth: Scout, in event: BoardEvent, proposing: Bool = true) {
        guard youth.status?.isWaitingForBoard == true else {
            byYouth[youth.id] = nil
            return
        }
        guard !isKept(youth.id) else { return }
        byYouth[youth.id] = Self.proposal(for: youth, in: event, whole: proposing)
    }

    /// Throw away any changes and propose a whole board, whether or not
    /// boards are proposed on selection. With proposals off it was asked for
    /// by hand, so it is the operator's.
    @MainActor
    public mutating func suggest(for youth: Scout, in event: BoardEvent, proposing: Bool = true) {
        guard youth.status?.isWaitingForBoard == true else { return }
        var draft = Self.proposal(for: youth, in: event, whole: true)
        draft.isEdited = !proposing
        byYouth[youth.id] = draft
    }

    /// Something a proposal is made from has changed (`fingerprint(of:)`).
    /// Proposals are dropped and the selected youth's is made again. It
    /// keeps its room while that room is there and free, whether the
    /// operator or the suggestion chose it, so a room freed earlier in the
    /// list does not move it; otherwise it takes the suggestion's. The
    /// operator's boards, and the frozen one, are left alone.
    @MainActor
    public mutating func refresh(selected youth: Scout?, in event: BoardEvent, proposing: Bool = true) {
        let roomID = youth.flatMap { byYouth[$0.id]?.roomID }
        byYouth = byYouth.filter { isKept($0.key) }
        guard let youth, youth.id != frozenID, youth.status?.isWaitingForBoard == true, byYouth[youth.id] == nil else {
            return
        }
        var draft = Self.proposal(for: youth, in: event, whole: proposing)
        if let roomID, event.room(id: roomID)?.isFree == true {
            draft.roomID = roomID
            draft.dropNoFreeRoomProblems()
        }
        byYouth[youth.id] = draft
    }

    /// The other waiting youth in queue order (pre-registered first), so a
    /// proposal keeps chairs and adults free for the boards to come.
    @MainActor
    private static func waiting(behind youth: Scout, in event: BoardEvent) -> [Scout] {
        event.scouts
            .filter { $0.id != youth.id && $0.status?.isWaitingForBoard == true }
            .sorted { $0.queueOrder < $1.queueOrder }
    }

    @MainActor
    private static func proposal(for youth: Scout, in event: BoardEvent, whole: Bool) -> BoardDraft {
        guard whole else {
            // Picking by hand: no one yet, but a free room of the right kind.
            return BoardDraft(roomID: event.rooms.first { $0.isFree && $0.boardType == youth.boardType }?.id)
        }
        let suggestion = BoardSuggestion(
            for: youth, adults: event.adults, rooms: event.rooms, waiting: waiting(behind: youth, in: event),
            freeSince: BoardSuggestion.freeSinceTimes(adults: event.adults, scouts: event.scouts))
        return BoardDraft(
            roomID: suggestion.roomID, chairID: suggestion.chairID, memberIDs: suggestion.memberIDs,
            problems: suggestion.problems)
    }

    /// What a proposal is made from: each room and whose board is in it;
    /// each adult's room, roles, unit, whom they introduce and Wood Badge,
    /// which the suggestion weighs (`Adult.cameForAnyBoard`, unit conflicts);
    /// and each youth's status, kind of board and unit. When any of it
    /// changes, the proposals the operator has not touched are made again.
    @MainActor
    public static func fingerprint(of event: BoardEvent) -> [String] {
        event.rooms.map { "\($0.id)|\($0.boardTypeText)|\($0.scoutName)" }
            + event.adults.map {
                "\($0.id)|\($0.room)|\($0.finalBoardRoleText)|\($0.projectReviewRoleText)|\($0.unitName)|"
                    + "\($0.supporting)|\($0.woodBadge)"
            }
            + event.scouts.map { "\($0.id)|\($0.statusText)|\($0.boardTypeText)|\($0.unitName)" }
    }

    // MARK: - The operator's changes

    /// Fill the Rest (SPEC.md D-12): keep who the operator put on the board
    /// and add a chair, if none of them may chair it, and members up to the
    /// working size, chosen as a suggestion would choose them.
    @MainActor
    public mutating func fill(for youth: Scout, in event: BoardEvent) {
        guard youth.status?.isWaitingForBoard == true, var draft = byYouth[youth.id] else { return }
        let picked = draft.memberIDs
        let fill = BoardSuggestion.fill(
            for: youth, adults: event.adults, picked: picked, waiting: Self.waiting(behind: youth, in: event),
            freeSince: BoardSuggestion.freeSinceTimes(adults: event.adults, scouts: event.scouts))
        var chairID = fill.chairID
        if chairID == nil, let boardType = youth.boardType {
            // No chair added: one of the picks may chair it. The one
            // chairing it already keeps the chair; otherwise the first.
            let mayChair = picked.filter { event.adult(id: $0)?.canChair(boardType) == true }
            chairID = mayChair.first { $0 == draft.chairID } ?? mayChair.first
        }
        draft.memberIDs = (fill.chairID.map { [$0] } ?? []) + picked + fill.memberIDs
        draft.chairID = chairID
        draft.roomID = draft.roomID ?? event.rooms.first { $0.isFree && $0.boardType == youth.boardType }?.id
        draft.problems = fill.problems
        draft.isEdited = true
        byYouth[youth.id] = draft
    }

    /// Empty the board, keeping its room.
    public mutating func clear(_ scoutID: Scout.ID) {
        guard var draft = byYouth[scoutID] else { return }
        draft.memberIDs = []
        draft.chairID = nil
        draft.problems = []
        draft.isEdited = true
        byYouth[scoutID] = draft
    }

    /// Put adults on the board, after those already on it. Anyone not
    /// signed in, or on it already, is skipped.
    @MainActor
    public mutating func add(_ adultIDs: [Adult.ID], for scoutID: Scout.ID, in event: BoardEvent) {
        guard var draft = byYouth[scoutID] else { return }
        let newIDs = adultIDs.filter { event.adult(id: $0) != nil && !draft.memberIDs.contains($0) }
        guard !newIDs.isEmpty else { return }
        draft.memberIDs += newIDs
        // The proposal's complaints no longer describe it; the inspector
        // checks the board as it now stands.
        draft.problems = []
        draft.isEdited = true
        byYouth[scoutID] = draft
    }

    public mutating func remove(_ adultIDs: Set<Adult.ID>, for scoutID: Scout.ID) {
        guard var draft = byYouth[scoutID] else { return }
        draft.memberIDs.removeAll { adultIDs.contains($0) }
        if let chairID = draft.chairID, adultIDs.contains(chairID) {
            draft.chairID = nil
        }
        // The proposal's complaints no longer describe it; the inspector
        // checks the board as it now stands.
        draft.problems = []
        draft.isEdited = true
        byYouth[scoutID] = draft
    }

    /// Can `adult` be made chair of this youth's board: on it, Chair for
    /// this kind of board, and not the one chairing it already
    /// (`BoardDraft.chair(among:for:)`)?
    @MainActor
    public func canMakeChair(_ adult: Adult, for youth: Scout, in event: BoardEvent) -> Bool {
        guard let draft = byYouth[youth.id], let boardType = youth.boardType,
              draft.memberIDs.contains(adult.id), adult.canChair(boardType) else { return false }
        let members = draft.memberIDs.compactMap { event.adult(id: $0) }
        return draft.chair(among: members, for: boardType) != adult.id
    }

    /// Make Chair: D-12 counts changing the chair as the operator's change.
    @MainActor
    public mutating func makeChair(_ adult: Adult, for youth: Scout, in event: BoardEvent) {
        guard canMakeChair(adult, for: youth, in: event) else { return }
        byYouth[youth.id]?.chairID = adult.id
        byYouth[youth.id]?.problems = []
        byYouth[youth.id]?.isEdited = true
    }

    /// Choose the board's room. Who sits on it is unchanged, so a proposal
    /// stays one and goes on following the event, in this room while it is
    /// free.
    public mutating func setRoom(_ roomID: Room.ID?, for scoutID: Scout.ID) {
        guard var draft = byYouth[scoutID], draft.roomID != roomID else { return }
        draft.roomID = roomID
        if roomID != nil {
            draft.dropNoFreeRoomProblems()
        }
        byYouth[scoutID] = draft
    }

    // MARK: - The event moving on

    /// The youth was seated or postponed: nothing is drawn up for them now.
    public mutating func discard(_ scoutID: Scout.ID) {
        byYouth[scoutID] = nil
    }

    public mutating func removeAll() {
        byYouth = [:]
    }

    /// Adults who went home or were taken off the event's list come off
    /// every board. Nothing else about a board changes: a proposal is still
    /// one, and the operator's board is still theirs.
    public mutating func takeOff(_ adultIDs: Set<Adult.ID>) {
        for scoutID in byYouth.keys {
            byYouth[scoutID]?.memberIDs.removeAll { adultIDs.contains($0) }
            if let chairID = byYouth[scoutID]?.chairID, adultIDs.contains(chairID) {
                byYouth[scoutID]?.chairID = nil
            }
        }
    }

    /// Let go of a room that is no longer there, after an undo.
    @MainActor
    public mutating func forgetRooms(missingFrom event: BoardEvent) {
        for scoutID in byYouth.keys {
            if let roomID = byYouth[scoutID]?.roomID, event.room(id: roomID) == nil {
                byYouth[scoutID]?.roomID = nil
            }
        }
    }

    /// After a rename the room keeps its record but not necessarily its ID.
    public mutating func roomRenamed(from oldID: Room.ID, to newID: Room.ID) {
        for scoutID in byYouth.keys where byYouth[scoutID]?.roomID == oldID {
            byYouth[scoutID]?.roomID = newID
        }
    }
}
