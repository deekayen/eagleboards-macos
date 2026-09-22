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
    /// chairs are all busy the answer is to promote someone in the Records
    /// window, never to hand the gavel to a Member.
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
            blockingProblems.append("\(scoutName) has already completed a board tonight.")
        case .postponed:
            blockingProblems.append("\(scoutName)'s board was postponed.")
        case nil:
            blockingProblems.append("\(scoutName) has an unknown status: '\(scout.statusText)'.")
        }

        guard let boardType = scout.boardType else {
            blockingProblems.append("\(scoutName) has no board type. Set Final Board or Proposal Review in the Records window.")
            return
        }

        if members.isEmpty {
            blockingProblems.append("No board members are selected.")
        }

        for member in members {
            if member.isDisabledForTonight {
                blockingProblems.append("\(member.fullName) has been disabled for tonight. Use Enable if they are back.")
            } else if member.isOnBoard {
                blockingProblems.append("\(member.fullName) is already on the board in room \(member.room).")
            }
            if member.role(for: boardType) == .unavailable {
                blockingProblems.append("\(member.fullName) is unavailable for \(boardType.label)s.")
            }
        }

        // Who is on the board comes before how many.
        let conflicts = BoardRules.unitConflicts(scoutUnitName: scout.unitName, members: members)
        if !conflicts.isEmpty {
            let names = conflicts.map(\.fullName).joined(separator: ", ")
            if !BoardRules.hasMemberFromOutsideUnit(scoutUnitName: scout.unitName, members: members) {
                blockingProblems.append(
                    "Every selected member is in \(scout.unitName), \(scoutName)'s own unit. "
                        + "A board must include at least one member from outside the unit "
                        + "(Guide to Advancement 8.0.3.0)."
                )
            } else {
                let count = conflicts.count
                warnings.append(Warning(
                    title: "\(count) member\(count == 1 ? " is" : "s are") from \(scoutName)'s unit",
                    detail: "\(names) \(count == 1 ? "is" : "are") in \(scout.unitName). This council does not "
                        + "permit adults from the scout's own unit on a board. Seating anyway falls back to the "
                        + "national rule, which this board still meets: at least one member is from outside the unit."
                ))
            }
        }

        qualifiedChairs = members.filter { $0.canChair(boardType) }
        if !members.isEmpty && qualifiedChairs.isEmpty {
            let roleColumn = boardType == .projectReview ? "Project" : "Final"
            blockingProblems.append(
                "None of the selected members is qualified to chair a \(boardType.label). "
                    + "Select someone whose \(roleColumn) role is Chair, or promote someone in the "
                    + "Records window by setting their \(roleColumn) role to Chair."
            )
        }

        let minimum = BoardRules.minimumMembers(for: boardType)
        switch BoardRules.checkSize(members.count, for: boardType) {
        case .tooFew where !members.isEmpty:
            blockingProblems.append(
                "Only \(members.count) member\(members.count == 1 ? "" : "s") selected; a \(boardType.label) needs \(minimum)."
            )
        case .tooMany:
            blockingProblems.append(
                "\(members.count) members selected; no more than \(BoardRules.boardMaximum) are permitted (Guide to Advancement 8.0.0.3)."
            )
        case .overPreferred:
            warnings.append(Warning(
                title: "\(members.count) members selected",
                detail: "Only \(minimum) are required for a \(boardType.label)."
            ))
        case .tooFew, .ok:
            break
        }

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

/// The board the scheduler proposes when a waiting youth is selected: a
/// chair, enough members to make a board, and a free room of the right kind.
public struct BoardSuggestion: Sendable, Equatable {
    public var chairID: String?
    public var memberIDs: [String] = []
    public var roomID: String?
    public var problems: [String] = []

    /// Pick from `adults` in sign-in order, skipping anyone already on a board,
    /// disabled, or from the youth's own unit.
    public init(for scout: Scout, adults: [Adult], rooms: [Room]) {
        guard let boardType = scout.boardType else {
            problems.append("\(scout.fullName) has no board type.")
            return
        }
        let label = boardType.label

        func pick(_ roles: Set<BoardRole>, count: Int, skipping taken: [String]) -> [String] {
            var picked: [String] = []
            for adult in adults where picked.count < count {
                guard adult.isAvailable, !taken.contains(adult.id),
                      BoardRules.unitConflicts(scoutUnitName: scout.unitName, members: [adult]).isEmpty,
                      let role = adult.role(for: boardType), roles.contains(role)
                else { continue }
                picked.append(adult.id)
            }
            return picked
        }

        let chair = pick([.chair], count: 1, skipping: []).first
        if chair == nil {
            problems.append("No \(label) chairs are available.")
        }
        chairID = chair

        let wanted = BoardRules.minimumMembers(for: boardType) - 1
        let alreadyTaken = chair.map { [$0] } ?? []
        var members = pick([.member], count: wanted, skipping: alreadyTaken)
        if members.count < wanted {
            members += pick([.member, .chair], count: wanted - members.count, skipping: alreadyTaken + members)
        }
        if members.count < wanted {
            problems.append("Only \(members.count) \(label) member\(members.count == 1 ? " is" : "s are") available.")
        }
        memberIDs = alreadyTaken + members

        roomID = rooms.first { $0.isFree && $0.boardType == boardType }?.id
        if roomID == nil {
            problems.append("No \(label) rooms are free.")
        }
    }
}

/// Finding a youth's unit leader and parents among the adults who signed in,
/// so someone can fetch them when the board is ready or has finished.
public enum AdultLocator {
    public enum Relation: String, Sendable {
        case leader = "Leader"
        case parent = "Parent"
    }

    public struct Match: Sendable, Identifiable {
        public let adult: Adult
        public let relation: Relation
        public var id: String { adult.id }
        /// Where to look: their board's room, or the main room.
        public var whereabouts: String { adult.room.isEmpty ? "Main room" : "Room \(adult.room)" }
    }

    /// A leader is an adult whose last name appears in the youth's Leader
    /// field and who is in the same unit (or whose first name appears there
    /// too). A parent is an adult in the same unit with the youth's last name.
    public static func locate(for scout: Scout, among adults: [Adult]) -> [Match] {
        let leaderText = scout.leader.lowercased()
        let scoutLast = scout.last.lowercased()
        var leaders: [Match] = []
        var parents: [Match] = []

        for adult in adults {
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
        return leaders + parents
    }
}

/// The yellow/red warning on a room card.
public enum RoomTimer {
    public enum State: Sendable, Equatable {
        case okay
        /// Past the yellow time.
        case warning
        /// Past the red time.
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
