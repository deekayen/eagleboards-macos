import Foundation

/// One row of one of the data files.
///
/// A record is its column values, keyed by the column names the files use.
/// Keeping them in a dictionary rather than as stored properties makes the
/// file format the single source of truth: what is on disk is what is in
/// memory, and the typed properties below are only readable names for it.
public protocol EventRecord: Identifiable, Hashable, Sendable where ID == String {
    /// The `Type` column, e.g. `SCOUT`.
    static var recordType: String { get }
    /// Every column this record writes, in file order.
    static var columns: [String] { get }
    /// Column values. A column absent here reads as the empty string.
    var fields: [String: String] { get set }
    init(fields: [String: String])
    /// Recompute the columns that are derived from others (e.g. `UnitName`).
    mutating func refreshDerivedFields()
    /// Fill in what a row read from disk may be missing.
    mutating func normalizeAfterLoad()
}

extension EventRecord {
    public subscript(column: String) -> String {
        get { fields[column] ?? "" }
        set { fields[column] = newValue }
    }

    public var id: String { self["ID"] }

    public var regTime: String {
        get { self["RegTime"] }
        set { self["RegTime"] = newValue }
    }

    public mutating func refreshDerivedFields() {}

    public mutating func normalizeAfterLoad() {
        refreshDerivedFields()
    }

    /// A blank record of this type, stamped as created at `now`.
    public static func blank(at now: Date) -> Self {
        let stamp = Timestamp.recordStamp(for: now)
        var record = Self(fields: [:])
        record["Type"] = recordType
        record["RegTime"] = stamp
        record["LastUpdateTime"] = stamp
        return record
    }

    /// Copy the named columns from `source`, skipping empty values -- a form
    /// that leaves a field blank does not wipe what was already on file.
    public mutating func update(from source: Self, columns names: [String]) {
        for name in names where !source[name].isEmpty {
            self[name] = source[name]
        }
        refreshDerivedFields()
    }
}

// MARK: - People

/// What youth and adults have in common: a name, contact details, a unit, and
/// an ID built from them.
public protocol PersonRecord: EventRecord {}

extension PersonRecord {
    public var first: String {
        get { self["First"] }
        set { self["First"] = newValue }
    }
    public var last: String {
        get { self["Last"] }
        set { self["Last"] = newValue }
    }
    public var email: String {
        get { self["Email"] }
        set { self["Email"] = newValue }
    }
    public var phone: String {
        get { self["Phone"] }
        set { self["Phone"] = newValue }
    }
    public var unitType: String {
        get { self["UnitType"] }
        set { self["UnitType"] = newValue }
    }
    public var unit: String {
        get { self["Unit"] }
        set { self["Unit"] = newValue }
    }
    /// Unit type and number as one label, e.g. `Troop1776`. Derived; this is
    /// what the same-unit rule compares.
    public var unitName: String { self["UnitName"] }
    public var room: String {
        get { self["Room"] }
        set { self["Room"] = newValue }
    }
    public var flags: String {
        get { self["Flags"] }
        set { self["Flags"] = newValue }
    }

    public var fullName: String { "\(first) \(last)" }

    /// `Troop1776` shortened to `T1776` for narrow columns. Unit types with no
    /// number keep the whole word, so District, Council and Community stay
    /// tellable apart.
    public var unitLabel: String { UnitLabel.short(unitName) }

    /// `Troop1776` spaced out to `Troop 1776` for display, the normal way a
    /// unit is written. `UnitName` itself stays unspaced: it is the data
    /// file's contract with the Java and Windows versions.
    public var unitDisplay: String { UnitLabel.spaced(unitName) }

    /// `SCOUT:Last:First:Unit`: the ID the Java app gave people. It keeps an ID
    /// it was handed unless that ID is empty, belongs to another record type,
    /// or is the placeholder a nameless record would get.
    public mutating func assignIDIfNeeded() {
        let current = id
        if current.isEmpty || !current.hasPrefix(Self.recordType) || current == "\(Self.recordType):::" {
            self["ID"] = Self.personID(last: last, first: first, unit: unit)
        }
    }

    /// No commas in an ID. The data files turn ',' into '~', so "Whitmore, Jr."
    /// came back from disk under a different ID than they signed in with, and
    /// signing in again after a restart made them a second person. '~' is what
    /// the files already hold, and what the Java app now uses too.
    public static func personID(last: String, first: String, unit: String) -> String {
        "\(recordType):\(last):\(first):\(unit)".replacingOccurrences(of: ",", with: "~")
    }

    public mutating func refreshDerivedFields() {
        self["UnitName"] = unitType + unit
    }

    public mutating func normalizeAfterLoad() {
        assignIDIfNeeded()
        refreshDerivedFields()
    }
}

public enum UnitLabel {
    public static func short(_ unitName: String) -> String {
        guard let firstDigit = unitName.firstIndex(where: \.isNumber),
              let initial = unitName.first, initial.isLetter,
              unitName[firstDigit...].allSatisfy(\.isNumber),
              unitName[..<firstDigit].allSatisfy(\.isLetter)
        else { return unitName }
        return String(initial) + unitName[firstDigit...]
    }

    /// A unit type with no number (District, Council, Community) is returned
    /// unchanged.
    public static func spaced(_ unitName: String) -> String {
        guard let firstDigit = unitName.firstIndex(where: \.isNumber),
              unitName[firstDigit...].allSatisfy(\.isNumber),
              unitName[..<firstDigit].allSatisfy(\.isLetter)
        else { return unitName }
        return unitName[..<firstDigit] + " " + unitName[firstDigit...]
    }
}

// MARK: - Youth

public struct Scout: PersonRecord {
    public static let recordType = "SCOUT"
    public static let columns = [
        "Type", "ID", "RegNum", "Last", "First", "Email", "Phone", "UnitType", "Unit", "UnitName",
        "DOB", "BoardType", "Leader", "RegTime", "LastUpdateTime", "Flags", "Room", "Status",
        "Result", "BoardChair", "BoardChairID", "BoardMembers", "BoardMembersIDs", "Notes",
    ]

    /// The columns a youth fills in at the sign-in station. Signing in again
    /// updates these and nothing else. No DOB (SPEC.md D-7) and no Phone
    /// (D-8): a birthdate or phone number sent by an older cached page is not
    /// copied, so a new youth's is empty, and one already on file is left
    /// alone (O-5).
    public static let signInColumns = ["First", "Last", "Unit", "UnitType", "Email", "Leader"]

    /// Columns kept in the data files but never shown, pre-filled or
    /// exported: nothing uses a youth's birthdate (SPEC.md D-7) or phone
    /// number (D-8). A value from before those rules stays on file (O-5).
    public static let withheldColumns = ["DOB", "Phone"]

    public var fields: [String: String]

    public init(fields: [String: String]) {
        self.fields = fields
    }

    /// `P3` or `W1`: pre-registered or walk-in, and the order they signed in
    /// within that group.
    public var regNum: String {
        get { self["RegNum"] }
        set { self["RegNum"] = newValue }
    }
    public var dateOfBirth: String {
        get { self["DOB"] }
        set { self["DOB"] = newValue }
    }
    public var boardTypeText: String {
        get { self["BoardType"] }
        set { self["BoardType"] = newValue }
    }
    public var boardType: BoardType? { BoardType(rawValue: boardTypeText) }
    /// The unit leader or Life-to-Eagle coach the youth named.
    public var leader: String {
        get { self["Leader"] }
        set { self["Leader"] = newValue }
    }
    public var statusText: String {
        get { self["Status"] }
        set { self["Status"] = newValue }
    }
    public var status: BoardStatus? {
        get { BoardStatus(rawValue: statusText) }
        set { statusText = newValue?.rawValue ?? "" }
    }
    /// The status as the screen says it; an unknown one as stored.
    public var statusLabel: String { status?.label ?? statusText }
    public var result: String {
        get { self["Result"] }
        set { self["Result"] = newValue }
    }
    public var boardChair: String {
        get { self["BoardChair"] }
        set { self["BoardChair"] = newValue }
    }
    public var boardChairID: String {
        get { self["BoardChairID"] }
        set { self["BoardChairID"] = newValue }
    }
    public var boardMembers: String {
        get { self["BoardMembers"] }
        set { self["BoardMembers"] = newValue }
    }
    /// Comma-separated adult IDs. The column is spelled `BoardMembersIDs` on
    /// disk; the spelling is kept so the Java app can still read the file.
    public var boardMemberIDs: String {
        get { self["BoardMembersIDs"] }
        set { self["BoardMembersIDs"] = newValue }
    }
    public var notes: String {
        get { self["Notes"] }
        set { self["Notes"] = newValue }
    }
    public var lastUpdateTime: String {
        get { self["LastUpdateTime"] }
        set { self["LastUpdateTime"] = newValue }
    }

    /// Restart the clock the room timers run on.
    public mutating func markUpdated(at now: Date) {
        lastUpdateTime = Timestamp.recordStamp(for: now)
    }

    /// Minutes since this record last changed status. For a waiting youth it is
    /// how long they have waited; once seated it is how long the board has run.
    public func minutesSinceLastUpdate(now: Date) -> Int? {
        Timestamp.minutesSince(recordStamp: lastUpdateTime, now: now)
    }

    public var isPreRegistered: Bool { regNum.hasPrefix("P") }
    public var isWalkIn: Bool { regNum.hasPrefix("W") }

    /// A copy for a file saved outside the data folder, with the withheld
    /// columns blank. They stay as columns, so the file keeps the data files'
    /// shape; the record itself is not changed.
    public var forExport: Scout {
        var copy = self
        for column in Self.withheldColumns {
            copy[column] = ""
        }
        return copy
    }
}

// MARK: - Adults

public struct Adult: PersonRecord {
    public static let recordType = "ADULT"
    public static let columns = [
        "Type", "ID", "Last", "First", "Email", "Phone", "UnitType", "Unit", "UnitName",
        "ProjectReview", "FinalBoard", "RegTime", "Room", "Flags", "Sel", "BoardHistory",
        // Per event, set at sign-in and never carried into the adult history.
        // Appended, as in the Java version, so older files still line up.
        "WoodBadge", "Supporting",
    ]

    /// The columns an adult fills in at the sign-in station.
    public static let signInColumns = ["First", "Last", "Unit", "UnitType", "Email", "Phone", "ProjectReview", "FinalBoard"]

    /// Take another record's name, unit, contact and roles, cleared ones
    /// too: what the event's adults and the adult history share (SPEC.md P-6).
    public mutating func copyFacts(from other: Adult) {
        for column in Self.signInColumns {
            self[column] = other[column]
        }
        refreshDerivedFields()
    }

    /// The sign-in form for an adult the operator adds by hand on the Adults
    /// page, for someone who would rather not use the tablet. It goes through
    /// `BoardEvent.registerAdult` as the tablet's does. A nil role is left for
    /// the adult history to fill in, or Member for someone new, so adding a
    /// known chair cannot demote them. `historyID` is the history record the
    /// form was filled in from, as the tablet's email lookup carries it, so a
    /// name corrected in the sheet still signs in the same person.
    public static func handSignInForm(
        historyID: String? = nil,
        first: String, last: String, email: String, phone: String, unitType: String, unit: String,
        finalBoard: BoardRole?, projectReview: BoardRole?, woodBadge: Bool
    ) -> [String: String] {
        [
            "ID": historyID ?? "",
            "First": first, "Last": last, "Email": email, "Phone": phone,
            "UnitType": unitType, "Unit": unit,
            "FinalBoard": finalBoard?.rawValue ?? "", "ProjectReview": projectReview?.rawValue ?? "",
            "WoodBadge": woodBadge ? "Y" : "",
        ]
    }

    public var fields: [String: String]

    public init(fields: [String: String]) {
        self.fields = fields
    }

    public var projectReviewRoleText: String {
        get { self["ProjectReview"] }
        set { self["ProjectReview"] = newValue }
    }
    public var finalBoardRoleText: String {
        get { self["FinalBoard"] }
        set { self["FinalBoard"] = newValue }
    }

    /// What this adult can do on a board of the given type.
    public func role(for boardType: BoardType) -> BoardRole? {
        switch boardType {
        case .finalBoard: BoardRole(rawValue: finalBoardRoleText)
        case .projectReview: BoardRole(rawValue: projectReviewRoleText)
        }
    }

    public func canChair(_ boardType: BoardType) -> Bool {
        role(for: boardType) == .chair
    }

    /// Dates this adult has signed in, as `(2026-08-25)(2026-09-22)`.
    public var boardHistory: String {
        get { self["BoardHistory"] }
        set { self["BoardHistory"] = newValue }
    }

    /// "Y" when this event counts toward a Wood Badge ticket item.
    public var woodBadge: String {
        get { self["WoodBadge"] }
        set { self["WoodBadge"] = newValue }
    }

    /// IDs of the youth this adult came to support (their Scoutmaster, say),
    /// separated by "|" because the data files turn commas into "~".
    public var supporting: String {
        get { self["Supporting"] }
        set { self["Supporting"] = newValue }
    }

    /// Said at sign-in they came to support this youth.
    public func supports(_ scoutID: String) -> Bool {
        supporting.split(separator: "|").contains { $0 == scoutID }
    }

    /// A Supporting list with one youth linked or unlinked. Order is kept and a
    /// youth is never listed twice. The same as withSupportLink in the Java
    /// version's process_seat.js.
    public static func withSupportLink(_ supporting: String, _ scoutID: String, linked: Bool) -> String {
        var ids = supporting.split(separator: "|").map(String.init).filter { !$0.isEmpty && $0 != scoutID }
        if linked {
            ids.append(scoutID)
        }
        return ids.joined(separator: "|")
    }

    /// Came to serve on any board: not here for a particular youth, or
    /// counting this event toward Wood Badge (then a volunteer first, whoever
    /// else they came with).
    public var cameForAnyBoard: Bool { woodBadge == "Y" || supporting.isEmpty }

    /// Stood down for the event with the Disable button.
    public var isDisabledForToday: Bool { room == disabledForTodayMarker }
    /// Sitting on a board right now.
    public var isOnBoard: Bool { !room.isEmpty && !isDisabledForToday }
    /// Free to be put on a board.
    public var isAvailable: Bool { room.isEmpty }

    /// Could be added to a board of this type right now: free, and did not
    /// say "No thanks" to it. The same refusals `BoardEvent.seatBoard` makes
    /// about a member, so the scheduler never offers someone it would refuse.
    public func canJoin(_ boardType: BoardType) -> Bool {
        isAvailable && role(for: boardType) != .unavailable
    }
}

// MARK: - Rooms

public struct Room: EventRecord {
    public static let recordType = "ROOM"
    public static let columns = ["Type", "ID", "Room", "BoardType", "Scout", "Leaders", "RegTime"]

    public var fields: [String: String]

    public init(fields: [String: String]) {
        self.fields = fields
    }

    public static func roomID(for name: String) -> String {
        "\(recordType):\(name)"
    }

    /// The room's name as people say it, e.g. `101` or `200A`.
    public var name: String {
        get { self["Room"] }
        set { self["Room"] = newValue }
    }
    public var boardTypeText: String {
        get { self["BoardType"] }
        set { self["BoardType"] = newValue }
    }
    public var boardType: BoardType? { BoardType(rawValue: boardTypeText) }
    /// Full name of the youth whose board has this room, or empty.
    public var scoutName: String {
        get { self["Scout"] }
        set { self["Scout"] = newValue }
    }
    /// Comma-separated full names of the adults on that board.
    public var leaderNames: String {
        get { self["Leaders"] }
        set { self["Leaders"] = newValue }
    }

    /// The Java UI treated "-" as empty too; kept so an old file still reads.
    public var isFree: Bool { scoutName.isEmpty || scoutName == "-" }
}

// MARK: - Settings

/// The single settings record, kept in `config.properties`.
public struct Config: EventRecord {
    public static let recordType = "CONFIG"
    public static let columns = [
        "Type", "ID", "Name", "RefreshTimeSecs", "ConveneRedMins",
        "ProjectYellowMins", "ProjectRedMins", "FinalYellowMins", "FinalRedMins",
    ]
    // RegisteredColor..PostponedHiColor followed here once. They are retired
    // (SPEC.md D-19): a file that still has them loads, and rendering it
    // leaves them out, because only these columns are written.

    /// Values used for any setting the file leaves out.
    ///
    /// The timer defaults come from the Guide to Advancement 8.0.3.0: members
    /// convene at least 30 minutes ahead to read the paperwork (#8), and a
    /// board "rarely should" run past 45 minutes (#9). The project review
    /// numbers are district practice; the Guide sets none for it.
    public static let defaults: [String: String] = [
        "Type": recordType, "ID": "DEFAULT", "Name": "DEFAULT",
        "RefreshTimeSecs": "30",
        "ConveneRedMins": "30",
        "ProjectYellowMins": "25", "ProjectRedMins": "40",
        "FinalYellowMins": "30", "FinalRedMins": "45",
    ]

    public var fields: [String: String]

    public init(fields: [String: String]) {
        var merged = Self.defaults
        for (column, value) in fields where !value.isEmpty {
            merged[column] = value
        }
        self.fields = merged
    }

    public static var standard: Config { Config(fields: [:]) }

    private func minutes(_ column: String) -> Int {
        Int(self[column].trimmingCharacters(in: .whitespaces)) ?? Int(Self.defaults[column] ?? "") ?? 0
    }

    private mutating func setMinutes(_ column: String, _ value: Int) {
        self[column] = String(max(0, value))
    }

    /// How often the sign-in station's lists refresh.
    public var refreshSeconds: Int {
        get { max(1, minutes("RefreshTimeSecs")) }
        set { self["RefreshTimeSecs"] = String(max(1, newValue)) }
    }
    /// How long a board may convene before the room card shows overdue. One
    /// limit, never just running long: past it the youth is being kept waiting.
    public var conveneRedMinutes: Int {
        get { minutes("ConveneRedMins") }
        set { setMinutes("ConveneRedMins", newValue) }
    }
    public var projectYellowMinutes: Int {
        get { minutes("ProjectYellowMins") }
        set { setMinutes("ProjectYellowMins", newValue) }
    }
    public var projectRedMinutes: Int {
        get { minutes("ProjectRedMins") }
        set { setMinutes("ProjectRedMins", newValue) }
    }
    public var finalYellowMinutes: Int {
        get { minutes("FinalYellowMins") }
        set { setMinutes("FinalYellowMins", newValue) }
    }
    public var finalRedMinutes: Int {
        get { minutes("FinalRedMins") }
        set { setMinutes("FinalRedMins", newValue) }
    }
}
