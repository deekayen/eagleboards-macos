import Foundation

/// Who may sit on a board, as pure functions so they can be tested headless.
///
/// These are enforced twice, on purpose. `SeatingReview` walks the operator
/// through them before a board is seated -- explaining each problem and, where
/// the rule allows, asking for confirmation -- and `EventNight.seatBoard`
/// refuses the hard ones again no matter how the request arrived. A board
/// seated past a rule is only discovered later, from the record of a review
/// that should not have happened. Both layers must agree.
public enum BoardRules {
    /// Guide to Advancement 8.0.0.3: a board of review has no fewer than three
    /// and no more than six members. Three is the district's working size.
    public static let boardMinimum = 3
    public static let boardMaximum = 6
    /// A project proposal review is not a board of review (GTA 9.0.2.4); this
    /// district runs it with two, under the same ceiling of six.
    public static let projectMinimum = 2

    public enum SizeVerdict: Equatable, Sendable {
        /// Below the minimum: refused.
        case tooFew
        /// Above six: refused. Not overridable -- it is a national ceiling.
        case tooMany
        /// Legal, but more than the working size, so worth confirming.
        case overPreferred
        case ok
    }

    public static func minimumMembers(for boardType: BoardType) -> Int {
        boardType == .projectReview ? projectMinimum : boardMinimum
    }

    public static func checkBoardSize(_ count: Int) -> SizeVerdict {
        verdict(count: count, minimum: boardMinimum)
    }

    public static func checkProjectSize(_ count: Int) -> SizeVerdict {
        verdict(count: count, minimum: projectMinimum)
    }

    public static func checkSize(_ count: Int, for boardType: BoardType) -> SizeVerdict {
        verdict(count: count, minimum: minimumMembers(for: boardType))
    }

    private static func verdict(count: Int, minimum: Int) -> SizeVerdict {
        if count < minimum { return .tooFew }
        if count > boardMaximum { return .tooMany }
        if count > minimum { return .overPreferred }
        return .ok
    }

    /// The members who share the scout's unit.
    ///
    /// A blank unit on either side is unknown, not a match: comparing blanks
    /// directly would block a board over missing data.
    public static func unitConflicts(scoutUnitName: String, members: [Adult]) -> [Adult] {
        guard !scoutUnitName.isEmpty else { return [] }
        return members.filter { !$0.unitName.isEmpty && $0.unitName == scoutUnitName }
    }

    /// Guide to Advancement 8.0.3.0 #2: a board must include at least one
    /// member not affiliated with the scout's unit. This council is stricter
    /// and forbids same-unit members entirely; the operator may override the
    /// council rule, but only down to this one. A blank unit counts as outside.
    public static func hasMemberFromOutsideUnit(scoutUnitName: String, members: [Adult]) -> Bool {
        guard !scoutUnitName.isEmpty else { return true }
        return members.contains { $0.unitName.isEmpty || $0.unitName != scoutUnitName }
    }

    /// Who may sit on this board and who must chair it, shared by seating a
    /// new board (`SeatingReview`) and changing an already-seated one's
    /// members (`ChangeMembersReview`). `sittingIn` is the room the board
    /// being edited already holds, if any: a member already there is not
    /// "already on another board" on that account alone.
    static func memberReview(
        scoutName: String, scoutUnitName: String, boardType: BoardType, members: [Adult], sittingIn currentRoom: String
    ) -> (blocking: [String], warnings: [SeatingReview.Warning], qualifiedChairs: [Adult]) {
        var blocking: [String] = []
        var warnings: [SeatingReview.Warning] = []

        if members.isEmpty {
            blocking.append("No board members are selected.")
        }

        for member in members {
            if member.isDisabledForTonight {
                blocking.append("\(member.fullName) has been disabled for today. Use Enable if they are back.")
            } else if member.isOnBoard && member.room != currentRoom {
                blocking.append("\(member.fullName) is already on the board in room \(member.room).")
            }
            if member.role(for: boardType) == .unavailable {
                blocking.append("\(member.fullName) is unavailable for \(boardType.label)s.")
            }
        }

        // Who is on the board comes before how many.
        let conflicts = unitConflicts(scoutUnitName: scoutUnitName, members: members)
        if !conflicts.isEmpty {
            let names = conflicts.map(\.fullName).joined(separator: ", ")
            if !hasMemberFromOutsideUnit(scoutUnitName: scoutUnitName, members: members) {
                blocking.append(
                    "Every selected member is in \(scoutUnitName), \(scoutName)'s own unit. "
                        + "A board must include at least one member from outside the unit "
                        + "(Guide to Advancement 8.0.3.0)."
                )
            } else {
                let count = conflicts.count
                warnings.append(SeatingReview.Warning(
                    title: "\(count) member\(count == 1 ? " is" : "s are") from \(scoutName)'s unit",
                    detail: "\(names) \(count == 1 ? "is" : "are") in \(scoutUnitName). This council does not "
                        + "permit adults from the scout's own unit on a board. Seating anyway falls back to the "
                        + "national rule, which this board still meets: at least one member is from outside the unit."
                ))
            }
        }

        let qualifiedChairs = members.filter { $0.canChair(boardType) }
        if !members.isEmpty && qualifiedChairs.isEmpty {
            let roleColumn = boardType == .projectReview ? "Project" : "Final"
            blocking.append(
                "None of the selected members is qualified to chair a \(boardType.label). "
                    + "Select someone whose \(roleColumn) role is Chair, or promote someone on the "
                    + "Adults page by setting their \(roleColumn) role to Chair."
            )
        }

        let minimum = minimumMembers(for: boardType)
        switch checkSize(members.count, for: boardType) {
        case .tooFew where !members.isEmpty:
            blocking.append(
                "Only \(members.count) member\(members.count == 1 ? "" : "s") selected; a \(boardType.label) needs \(minimum)."
            )
        case .tooMany:
            blocking.append(
                "\(members.count) members selected; no more than \(boardMaximum) are permitted (Guide to Advancement 8.0.0.3)."
            )
        case .overPreferred:
            warnings.append(SeatingReview.Warning(
                title: "\(members.count) members selected",
                detail: "Only \(minimum) are required for a \(boardType.label)."
            ))
        case .tooFew, .ok:
            break
        }

        return (blocking, warnings, qualifiedChairs)
    }
}

/// Everything the operator needs to decide before a board is seated, worked
/// out in one pass so the Seat Board sheet can show it all at once rather than
/// one alert at a time.
public struct SeatingReview: Sendable {
    /// Problems that stop the board being seated. Nothing overrides these.
    public private(set) var blockingProblems: [String] = []
    /// Legal but worth a second look. The operator must acknowledge each one.
    public private(set) var warnings: [Warning] = []
    /// Selected members qualified to chair this board type. The chair must be
    /// one of these: the Chair designation is binding, and when the qualified
    /// chairs are all busy the answer is to promote someone on the Adults
    /// page, never to hand the gavel to a Member.
    public private(set) var qualifiedChairs: [Adult] = []

    public struct Warning: Sendable, Hashable, Identifiable {
        public let title: String
        public let detail: String
        public var id: String { title }
    }

    public var canSeat: Bool { blockingProblems.isEmpty }

    public init(scout: Scout, members: [Adult], room: Room?) {
        let scoutName = scout.fullName

        switch scout.status {
        case .registered, .verified:
            break
        case .seated:
            blockingProblems.append("\(scoutName)'s board is already seated.")
        case .inProgress:
            blockingProblems.append("\(scoutName) is in a review now, in room \(scout.room).")
        case .completed:
            blockingProblems.append("\(scoutName) has already completed a board today.")
        case .postponed:
            blockingProblems.append("\(scoutName)'s board was postponed.")
        case nil:
            blockingProblems.append("\(scoutName) has an unknown status: '\(scout.statusText)'.")
        }

        guard let boardType = scout.boardType else {
            blockingProblems.append("\(scoutName) has no board type. Set Final or Project in the Board column of the Youth page.")
            return
        }

        let review = BoardRules.memberReview(
            scoutName: scoutName, scoutUnitName: scout.unitName, boardType: boardType, members: members, sittingIn: "")
        blockingProblems += review.blocking
        warnings += review.warnings
        qualifiedChairs = review.qualifiedChairs

        if let room {
            if !room.isFree {
                blockingProblems.append("Room \(room.name) is already in use by \(room.scoutName).")
            } else if room.boardType != boardType {
                warnings.append(Warning(
                    title: "Room \(room.name) is a \(room.boardType?.label ?? room.boardTypeText) room",
                    detail: "\(scoutName) is here for a \(boardType.label)."
                ))
            }
        } else {
            blockingProblems.append("No room is selected.")
        }
    }
}

/// Everything the operator needs to decide before changing who sits on a
/// board that is already Seated or InProgress: the same composition rules
/// `SeatingReview` checks, but the room is the one the board already holds,
/// not a choice, and the youth's status is expected to be past waiting.
public struct ChangeMembersReview: Sendable {
    public private(set) var blockingProblems: [String] = []
    public private(set) var warnings: [SeatingReview.Warning] = []
    public private(set) var qualifiedChairs: [Adult] = []

    public var canApply: Bool { blockingProblems.isEmpty }

    public init(scout: Scout, members: [Adult]) {
        let scoutName = scout.fullName

        guard scout.status == .seated || scout.status == .inProgress else {
            blockingProblems.append("\(scoutName)'s board members can only be changed while seated or in review.")
            return
        }
        guard let boardType = scout.boardType else {
            blockingProblems.append("\(scoutName) has no board type.")
            return
        }

        let review = BoardRules.memberReview(
            scoutName: scoutName, scoutUnitName: scout.unitName, boardType: boardType, members: members, sittingIn: scout.room)
        blockingProblems = review.blocking
        warnings = review.warnings
        qualifiedChairs = review.qualifiedChairs
    }
}

/// The board the scheduler proposes when a waiting youth is selected: a
/// chair, enough members to make a board, and a free room of the right kind.
///
/// It used to take the first qualified chair and the first adults whose role
/// was Member, in sign-in order. A Final board's Member is often a project
/// chair, so the first Final board of the night could take both project
/// chairs and leave every project review without one; and it ignored the
/// troops of the youth still waiting.
///
/// Now every legal board is considered -- one qualified chair plus the
/// working number of members, none from the youth's unit -- and the one
/// chosen is, in order:
///
///  1. the one leaving the most of the `waiting` youth (the OTHER waiting
///     youth, in queue order) able to get a full board at once from the
///     adults left over, so chairs and troop conflicts both count;
///  2. then the one using up the fewest chair qualifications, so member-only
///     adults fill member seats and a single-type chair is used before one
///     who can chair either;
///  3. then the one whose adults could serve the fewest other waiting youth;
///  4. then volunteers who came for any board (`Adult.cameForAnyBoard`: not
///     linked to a youth, or Wood Badge), so they are not the ones left idle;
///  5. then the adults who have waited longest to volunteer since they were
///     last free (`freeSinceTimes`), and sign-in order within a minute.
///
/// With no full board to be had it proposes what it can, in the same
/// preference order, and says what is short. The same algorithm, with the
/// same test cases (SPEC.md D-5, `SharedCaseTests`), is `proposeBoard` in
/// the Java version's process_seat.js and `SchedulerLogic.AutoSelect` in the
/// Windows version.
public struct BoardSuggestion: Sendable, Equatable {
    public var chairID: String?
    /// The whole board, chair first.
    public var memberIDs: [String] = []
    public var roomID: String?
    public var problems: [String] = []

    private struct Candidate {
        let adult: Adult
        let chairs: Int
        let useful: Int
        let since: String
        let order: Int
        var profile: String {
            "\(adult.unitName)|\(adult.role(for: .finalBoard)?.rawValue ?? "")|\(adult.role(for: .projectReview)?.rawValue ?? "")"
        }
    }

    private static func sharesUnit(_ adult: Adult, _ scout: Scout) -> Bool {
        !BoardRules.unitConflicts(scoutUnitName: scout.unitName, members: [adult]).isEmpty
    }

    private static func canSit(_ adult: Adult, for scout: Scout) -> Bool {
        guard let boardType = scout.boardType, let role = adult.role(for: boardType) else { return false }
        return (role == .chair || role == .member) && !sharesUnit(adult, scout)
    }

    private static func canChair(_ adult: Adult, for scout: Scout) -> Bool {
        guard let boardType = scout.boardType else { return false }
        return adult.role(for: boardType) == .chair && !sharesUnit(adult, scout)
    }

    private static func membersBesideChair(_ boardType: BoardType) -> Int {
        BoardRules.minimumMembers(for: boardType) - 1
    }

    /// How many of `waiting`, in queue order, can each still get a full board
    /// at once from `pool` (sorted by preference).
    private static func countSeatable(_ pool: [Candidate], _ waiting: [Scout]) -> Int {
        var used = Set<String>()
        var seated = 0
        for youth in waiting {
            guard let boardType = youth.boardType,
                  let chair = pool.first(where: { !used.contains($0.adult.id) && canChair($0.adult, for: youth) })
            else { continue }
            let need = membersBesideChair(boardType)
            let members = pool.filter {
                !used.contains($0.adult.id) && $0.adult.id != chair.adult.id && canSit($0.adult, for: youth)
            }.prefix(need)
            if members.count == need {
                used.insert(chair.adult.id)
                used.formUnion(members.map(\.adult.id))
                seated += 1
            }
        }
        return seated
    }

    /// When each adult last became free to volunteer, for the waited-longest
    /// tie-break: when they signed in, or when the last board they sat on was
    /// completed, whichever is later. Nothing stores the second, so it is read
    /// from the Completed youth, whose last-update time is when the result was
    /// recorded and whose member list names who sat. A reset board never
    /// happened and keeps no member list, so the adult's earlier wait stands.
    ///
    /// Times are the records' `yyyy-MM-dd_HH:mm±hhmm` stamps, which sort as
    /// text within one event night. The member list is comma-joined and read
    /// back from the files with '~'; an ID whose name had a comma also holds a
    /// '~', so each whole ID is looked for between separators rather than
    /// splitting the list. The same helper is freeSinceTimes in the Java
    /// version and SchedulerLogic.FreeSinceTimes in the Windows version.
    public static func freeSinceTimes(adults: [Adult], scouts: [Scout]) -> [String: String] {
        let boards = scouts
            .filter { $0.status == .completed && !$0.boardMemberIDs.isEmpty && !$0.lastUpdateTime.isEmpty }
            .map { (list: "~" + $0.boardMemberIDs.replacingOccurrences(of: ",", with: "~") + "~", finished: $0.lastUpdateTime) }
        var since: [String: String] = [:]
        for adult in adults {
            let needle = "~" + adult.id + "~"
            since[adult.id] = boards
                .filter { $0.list.contains(needle) }
                .map(\.finished)
                .reduce(adult.regTime) { max($0, $1) }
        }
        return since
    }

    /// Every free adult, best first for a seat: fewest chair qualifications,
    /// then those who could sit for the fewest `waiting` youth, then those
    /// who came for any board, then the longest since they were last free,
    /// then sign-in order. Each keeps the keys it was ranked on, since the
    /// suggestion scores whole boards with them.
    private static func rankFreeAdults(_ adults: [Adult], waiting: [Scout], freeSince: [String: String]) -> [Candidate] {
        adults.enumerated()
            .filter { $0.element.isAvailable }
            .map { order, adult in
                Candidate(
                    adult: adult,
                    chairs: BoardType.allCases.filter { adult.role(for: $0) == .chair }.count,
                    useful: waiting.filter { canSit(adult, for: $0) }.count,
                    since: freeSince[adult.id] ?? "",
                    order: order)
            }
            .sorted {
                ($0.chairs, $0.useful, $0.adult.cameForAnyBoard ? 0 : 1, $0.since, $0.order)
                    < ($1.chairs, $1.useful, $1.adult.cameForAnyBoard ? 0 : 1, $1.since, $1.order)
            }
    }

    /// Choose from `adults` (in sign-in order), skipping anyone on a board,
    /// disabled for tonight, Unavailable, or from the youth's own unit.
    /// `freeSince` is from `freeSinceTimes`; an adult missing from it sorts first.
    public init(for scout: Scout, adults: [Adult], rooms: [Room], waiting: [Scout] = [], freeSince: [String: String] = [:]) {
        guard let boardType = scout.boardType else {
            problems.append("\(scout.fullName) has no board type.")
            return
        }
        let label = boardType.label
        let need = Self.membersBesideChair(boardType)

        let pool = Self.rankFreeAdults(adults, waiting: waiting, freeSince: freeSince)
        let chairs = pool.filter { Self.canChair($0.adult, for: scout) }
        let sitters = pool.filter { Self.canSit($0.adult, for: scout) }

        var best: [Candidate]?
        var bestScore = (seatable: -1, chairsKept: 0, flexibility: 0)
        var triedChairs = Set<String>()
        for chair in chairs where triedChairs.insert(chair.profile).inserted {
            let others = sitters.filter { $0.adult.id != chair.adult.id }
            var combo: [Candidate] = []

            func visit(_ start: Int) {
                if combo.count == need {
                    let board = [chair] + combo
                    let taken = Set(board.map(\.adult.id))
                    let score = (
                        seatable: Self.countSeatable(pool.filter { !taken.contains($0.adult.id) }, waiting),
                        chairsKept: -board.map(\.chairs).reduce(0, +),
                        flexibility: -board.map(\.useful).reduce(0, +))
                    if best == nil || score > bestScore {
                        bestScore = score
                        best = board
                    }
                    return
                }
                // Adults from the same unit with the same roles are
                // interchangeable here, so only the first is tried in each
                // seat: the same answer from a far smaller search.
                var tried = Set<String>()
                for index in start..<others.count where tried.insert(others[index].profile).inserted {
                    combo.append(others[index])
                    visit(index + 1)
                    combo.removeLast()
                }
            }
            visit(0)
        }

        if let best {
            chairID = best[0].adult.id
            memberIDs = best.map(\.adult.id)
        } else {
            // No full board: what there is, best first, and what is short.
            chairID = chairs.first?.adult.id
            if chairID == nil {
                problems.append("No \(label) chairs are available.")
            }
            let members = sitters.filter { $0.adult.id != chairID }.prefix(need).map(\.adult.id)
            if members.count < need {
                problems.append("Only \(members.count) \(label) member\(members.count == 1 ? " is" : "s are") available.")
            }
            memberIDs = (chairID.map { [$0] } ?? []) + members
        }

        roomID = rooms.first { $0.isFree && $0.boardType == boardType }?.id
        if roomID == nil {
            problems.append("No \(label) rooms are free.")
        }
    }

    /// What Fill the Rest adds to a board (SPEC.md D-12).
    public struct Fill: Sendable, Equatable {
        /// The chair added, or nil when one of the picks may chair this kind
        /// of board, or no one free may.
        public var chairID: String?
        /// The members added beside the chair, best first. Never a pick.
        public var memberIDs: [String] = []
        public var problems: [String] = []
    }

    /// Fill the Rest (SPEC.md D-12): keep the adults the operator chose and
    /// complete the board around them -- a chair if none of `picked` may chair
    /// this kind of board, then members up to the working size, in the
    /// suggestion's order of preference. Unlike the suggestion it does not
    /// weigh whole boards: the operator has already decided who the board is
    /// built around. With no chair to add, the chair's seat counts as a
    /// member's, so it asks for one more member than it would beside a chair.
    /// The same as `fillBoard` in the Java version's process_seat.js and
    /// `SchedulerLogic.FillBoard` in the Windows version.
    public static func fill(
        for scout: Scout, adults: [Adult], picked: [Adult.ID], waiting: [Scout] = [], freeSince: [String: String] = [:]
    ) -> Fill {
        var fill = Fill()
        guard let boardType = scout.boardType else {
            fill.problems.append("\(scout.fullName) has no board type.")
            return fill
        }
        let label = boardType.label
        let pool = rankFreeAdults(adults, waiting: waiting, freeSince: freeSince).filter { !picked.contains($0.adult.id) }

        if !adults.contains(where: { picked.contains($0.id) && $0.role(for: boardType) == .chair }) {
            fill.chairID = pool.first { canChair($0.adult, for: scout) }?.adult.id
            if fill.chairID == nil {
                fill.problems.append("No \(label) chairs are available.")
            }
        }

        let wanted = max(0, BoardRules.minimumMembers(for: boardType) - picked.count - (fill.chairID == nil ? 0 : 1))
        fill.memberIDs = pool.filter { $0.adult.id != fill.chairID && canSit($0.adult, for: scout) }
            .prefix(wanted).map(\.adult.id)
        if fill.memberIDs.count < wanted {
            let count = fill.memberIDs.count
            fill.problems.append("Only \(count) \(label) member\(count == 1 ? " is" : "s are") available.")
        }
        return fill
    }
}

/// Finding a youth's unit leader and parents among the adults who signed in,
/// so someone can fetch them when the board is ready or has finished.
public enum AdultLocator {
    public enum Relation: String, Sendable {
        /// Said at sign-in they came to support this youth.
        case supporting = "Supporting"
        case leader = "Leader"
        case parent = "Parent"
    }

    public struct Match: Sendable, Identifiable {
        public let adult: Adult
        public let relation: Relation
        public var id: String { adult.id }
        /// Where to look: their board's room, or the main room.
        public var whereabouts: String {
            adult.room.isEmpty ? "Main room" : adult.isDisabledForTonight ? "marked as gone home" : "Room \(adult.room)"
        }
    }

    /// A leader is an adult whose last name appears in the youth's Leader
    /// field and who is in the same unit (or whose first name appears there
    /// too). A parent is an adult in the same unit with the youth's last name.
    /// Adults who said at sign-in they came to support this youth come first,
    /// and are not guessed at again.
    public static func locate(for scout: Scout, among adults: [Adult]) -> [Match] {
        let leaderText = scout.leader.lowercased()
        let scoutLast = scout.last.lowercased()
        var leaders: [Match] = []
        var parents: [Match] = []

        var supporting: [Match] = []

        for adult in adults {
            if adult.supports(scout.id) {
                supporting.append(Match(adult: adult, relation: .supporting))
                continue
            }
            let adultLast = adult.last.lowercased()
            let adultFirst = adult.first.lowercased()
            let sameUnit = !scout.unitName.isEmpty && adult.unitName == scout.unitName
            if !adultLast.isEmpty, leaderText.contains(adultLast),
               sameUnit || (!adultFirst.isEmpty && leaderText.contains(adultFirst)) {
                leaders.append(Match(adult: adult, relation: .leader))
            } else if sameUnit, !scoutLast.isEmpty, adultLast == scoutLast {
                parents.append(Match(adult: adult, relation: .parent))
            }
        }
        return supporting + leaders + parents
    }
}

/// The running-long and overdue warnings on a room card. The settings keep
/// their old names: running long is the "Yellow" time, overdue the "Red".
public enum RoomTimer {
    public enum State: Sendable, Equatable {
        case okay
        /// Running long: past the yellow time.
        case warning
        /// Overdue: past the red time.
        case overdue
    }

    /// The clock is the youth's minutes since last update, so it restarts by
    /// itself at each transition and times the two phases apart:
    ///
    ///   Seated      the board is convening. One cap, `ConveneRedMins`, and no
    ///               yellow: it is a limit, not a target.
    ///   InProgress  the youth is in the room. Yellow and red per board type.
    ///
    /// Returns nil when nothing is being timed (other statuses, or a limit of 0).
    public static func state(status: BoardStatus?, boardType: BoardType?, minutes: Int, config: Config) -> State? {
        let yellow: Int
        let red: Int
        switch status {
        case .seated:
            yellow = config.conveneRedMinutes
            red = config.conveneRedMinutes
        case .inProgress:
            if boardType == .finalBoard {
                yellow = config.finalYellowMinutes
                red = config.finalRedMinutes
            } else {
                yellow = config.projectYellowMinutes
                red = config.projectRedMinutes
            }
        default:
            return nil
        }
        guard yellow > 0 else { return nil }
        if red > 0 && minutes >= red { return .overdue }
        if minutes >= yellow { return .warning }
        return .okay
    }
}
