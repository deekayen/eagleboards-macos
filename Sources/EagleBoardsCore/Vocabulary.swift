// The words the records store. Every raw value here is written to disk
// exactly as the Java Eagle Board Scheduler wrote it, so a data folder can be
// opened by either program.

/// Where a youth is in the event. Stored in the `Status` column.
///
/// Registered -> Seated -> InProgress -> Completed, or Registered -> Postponed.
/// Seating and starting are two steps on purpose: seating gives the board the
/// room and the paperwork while the scout waits outside (Guide to Advancement
/// 8.0.3.0 #8); Start Review brings the scout in. Keeping them apart is what
/// lets the two phases be timed separately.
public enum BoardStatus: String, CaseIterable, Sendable {
    case registered = "Registered"
    /// Legacy only. The Java app once had a Verify step; nothing sets this now,
    /// but a record carried over from an old event must not get stuck.
    case verified = "Verified"
    case seated = "Seated"
    case inProgress = "InProgress"
    case completed = "Completed"
    case postponed = "Postponed"

    /// Order used when sorting by status.
    public var sortRank: Int {
        switch self {
        case .registered: 0
        case .verified: 1
        case .seated: 2
        case .inProgress: 3
        case .completed: 4
        case .postponed: 5
        }
    }

    /// Can a board be seated for a youth in this state?
    public var isWaitingForBoard: Bool {
        self == .registered || self == .verified
    }

    /// Finished for the event, one way or another.
    public var isFinished: Bool {
        self == .completed || self == .postponed
    }

    /// A board is sitting: it holds a room and its members.
    public var holdsRoom: Bool {
        self == .seated || self == .inProgress
    }

    /// What the screen calls it, the same word in all three versions (SPEC.md
    /// D-13): badges, their accessibility labels, the Youth page's Status
    /// menu and alerts. The data files keep the raw value.
    public var label: String {
        switch self {
        case .registered, .verified: "Waiting"
        case .seated: "Seated"
        case .inProgress: "In review"
        case .completed: "Completed"
        case .postponed: "Postponed"
        }
    }
}

/// The step that moves a youth's board along from where it is: the one
/// thing the operator does next. The scheduler's Next Step button and the
/// Return key perform it.
public enum BoardStep: Sendable, Equatable {
    case seat
    case startReview
    case complete

    public var title: String {
        switch self {
        case .seat: "Seat Board…"
        case .startReview: "Start Review"
        case .complete: "Complete…"
        }
    }
}

extension BoardStatus {
    /// Nil once the board is finished: nothing moves it along from there.
    public var nextStep: BoardStep? {
        switch self {
        case .registered, .verified: .seat
        case .seated: .startReview
        case .inProgress: .complete
        case .completed, .postponed: nil
        }
    }
}

/// What kind of review a youth came for. Stored in `BoardType`, on scouts and
/// on rooms, and it keys the room timers.
public enum BoardType: String, CaseIterable, Sendable, Identifiable {
    /// The Eagle Scout board of review.
    case finalBoard = "Final"
    /// The service project proposal review. Not a board of review
    /// (Guide to Advancement 9.0.2.4), so it has its own size rules.
    case projectReview = "Project"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .finalBoard: "Final Board"
        case .projectReview: "Proposal Review"
        }
    }
}

/// What an adult has said they can do for one kind of board. Stored in
/// `FinalBoard` and `ProjectReview` on adults.
public enum BoardRole: String, CaseIterable, Sendable, Identifiable {
    case chair = "Chair"
    case member = "Member"
    case unavailable = "Unavailable"

    public var id: String { rawValue }
}

/// How a board ended. Stored in `Result`.
public enum BoardResult: String, CaseIterable, Sendable, Identifiable {
    case approved = "Approved"
    case adjourned = "Adjourned"
    case notApproved = "NotApproved"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .notApproved: "Not Approved"
        default: rawValue
        }
    }
}

/// Unit types offered on the sign-in forms. District, Council and Community
/// are roles rather than numbered units, so they are offered to adults only
/// and carry no unit number.
public enum UnitType: String, CaseIterable, Sendable, Identifiable {
    case troop = "Troop"
    case post = "Post"
    case crew = "Crew"
    case ship = "Ship"
    case pack = "Pack"
    case district = "District"
    case council = "Council"
    case community = "Community"

    public var id: String { rawValue }

    public static let youthChoices: [UnitType] = [.troop, .post, .crew, .ship]

    public var hasUnitNumber: Bool {
        switch self {
        case .district, .council, .community: false
        default: true
        }
    }
}

/// The value an adult's `Room` holds when the Disable button has stood them
/// down for the event. It is a marker, not a room anyone can be sent to.
public let disabledForTodayMarker = "N/A"
