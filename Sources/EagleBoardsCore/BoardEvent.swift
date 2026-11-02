import Foundation
import Observation

/// A refusal, worded for the operator.
public struct EventError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// One event: everyone who has signed in, the rooms, and every board.
///
/// All state lives on the main actor. The scheduler window reads it directly,
/// and the check-in server hops onto the main actor to register someone, so a
/// sign-in shows up on the operator's screen the moment it happens. Every
/// change is written to disk before the call returns, as the Java app did, so
/// quitting at any moment loses nothing.
@MainActor
@Observable
public final class BoardEvent {
    public let folder: DataFolder
    /// `YYYY-MM-DD`, the name of this event's folder.
    public let date: String

    /// Youth who have signed in at this event (`scouts.csv`).
    public private(set) var scouts: [Scout] = []
    /// Youth pre-registered for this event, from SignUpGenius (`scouts_scheduled.csv`).
    public private(set) var scheduledScouts: [Scout] = []
    /// Adults who have signed in at this event (`adults.csv`).
    public private(set) var adults: [Adult] = []
    /// Every adult who has ever signed in (`Master_AdultHistory.csv`).
    public private(set) var adultHistory: [Adult] = []
    public private(set) var rooms: [Room] = []
    public private(set) var config: Config = .standard
    /// This open found no adult history in the data folder and started a new,
    /// empty one (SPEC.md D-9), which the app says, naming where. False on
    /// every later open.
    public let createdAdultHistory: Bool

    @ObservationIgnored private let clock: @Sendable () -> Date

    /// Opens (creating if needed) the event's folder inside `folder`, and reads
    /// every data file into memory. A file that does not exist reads as empty
    /// (as the standard settings, for the config), and each one still missing
    /// after the read is written out.
    ///
    /// - Parameters:
    ///   - folder: the data folder that holds the event folders, the adult
    ///     history, and the settings.
    ///   - date: the event's date as `YYYY-MM-DD`, which names its folder.
    ///     Nothing here checks the format.
    ///   - clock: the source of the current time. The default is the system
    ///     clock; tests pass a fixed one.
    /// - Throws: the Foundation error when the event folder cannot be created
    ///   or a data file that exists cannot be read, and `EventError` ("Could
    ///   not save ...") when writing a missing file fails.
    public init(folder: DataFolder, date: String, clock: @escaping @Sendable () -> Date = { Date() }) throws {
        self.folder = folder
        self.date = date
        self.clock = clock
        createdAdultHistory = CSVFile.isMissing(at: folder.adultHistoryURL)

        try FileManager.default.createDirectory(at: folder.eventFolder(date), withIntermediateDirectories: true)
        scouts = try CSVFile.read(Scout.self, from: folder.youthURL(event: date))
        scheduledScouts = try CSVFile.read(Scout.self, from: folder.scheduledYouthURL(event: date))
        adults = try CSVFile.read(Adult.self, from: folder.adultsURL(event: date))
        adultHistory = try CSVFile.read(Adult.self, from: folder.adultHistoryURL)
        rooms = try CSVFile.read(Room.self, from: folder.roomsURL(event: date))
        config = try PropertiesFile.read(from: folder.configURL)

        // Leave a complete, readable folder behind even if nothing happens
        // at this event -- the Java app created every file at startup too.
        for table in Table.allCases where CSVFile.isMissing(at: url(of: table)) {
            try save(table)
        }
    }

    public var now: Date { clock() }

    // MARK: - Files

    public enum Table: CaseIterable, Sendable {
        case youth, scheduledYouth, adults, adultHistory, rooms, config
    }

    public func url(of table: Table) -> URL {
        switch table {
        case .youth: folder.youthURL(event: date)
        case .scheduledYouth: folder.scheduledYouthURL(event: date)
        case .adults: folder.adultsURL(event: date)
        case .adultHistory: folder.adultHistoryURL
        case .rooms: folder.roomsURL(event: date)
        case .config: folder.configURL
        }
    }

    private func save(_ tables: Table...) throws {
        for table in tables {
            do {
                switch table {
                case .youth: try CSVFile.write(scouts, to: url(of: table))
                case .scheduledYouth: try CSVFile.write(scheduledScouts, to: url(of: table))
                case .adults: try CSVFile.write(adults, to: url(of: table))
                case .adultHistory: try CSVFile.write(adultHistory, to: url(of: table))
                case .rooms: try CSVFile.write(rooms, to: url(of: table))
                case .config: try PropertiesFile.write(config, to: url(of: table))
                }
            } catch {
                throw EventError("Could not save \(url(of: table).lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Lookups

    public func scout(id: String) -> Scout? { scouts.first { $0.id == id } }
    public func adult(id: String) -> Adult? { adults.first { $0.id == id } }
    public func room(id: String) -> Room? { rooms.first { $0.id == id } }
    public func room(named name: String) -> Room? { rooms.first { $0.name == name } }

    /// The youth whose board is in this room right now.
    public func occupant(of room: Room) -> Scout? {
        guard !room.isFree else { return nil }
        return scouts.first { $0.room == room.name && ($0.status == .seated || $0.status == .inProgress) }
    }

    /// The names on the board sitting in this room, in the board's order.
    public func memberNames(in room: Room) -> [String] {
        room.memberNames(occupant: occupant(of: room), among: adults)
    }

    /// A usable email for matching, or nil for a blank or the form's `NONE`.
    public static func matchableEmail(_ email: String) -> String? {
        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cleaned.isEmpty || cleaned == "none" ? nil : cleaned
    }

    /// The pre-registration a youth's email matches, for filling in the form.
    public func scheduledYouth(matchingEmail email: String) -> Scout? {
        guard let wanted = Self.matchableEmail(email) else { return nil }
        return scheduledScouts.first { Self.matchableEmail($0.email) == wanted }
    }

    /// The history record an adult's email matches, for filling in the form.
    public func knownAdult(matchingEmail email: String) -> Adult? {
        guard let wanted = Self.matchableEmail(email) else { return nil }
        return adultHistory.first { Self.matchableEmail($0.email) == wanted }
    }

    /// Adults in the history matching every word of `query` in their name,
    /// email or unit, sorted by last name, then first: what the Add Adult
    /// sheet offers to fill itself in from. An empty query matches no one.
    public func historyMatches(for query: String, limit: Int = 8) -> [Adult] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let found = adultHistory.filter { adult in
            let fields = [adult.first, adult.last, adult.email, adult.unitName, adult.unitLabel, adult.unitDisplay]
            return words.allSatisfy { word in fields.contains { $0.localizedCaseInsensitiveContains(word) } }
        }
        return Array(
            found.sorted {
                ($0.last.lowercased(), $0.first.lowercased()) < ($1.last.lowercased(), $1.first.lowercased())
            }
            .prefix(limit))
    }

    /// The youth an adult may say at sign-in they will introduce (SPEC.md D-23): everyone
    /// who RSVP'd, plus the event's walk-ins, leaving out anyone already
    /// finished (Completed or Postponed) and anyone here for a project
    /// proposal, which has no introduction. The sign-in's record wins over the
    /// RSVP with the same ID; sorted by last name, then first.
    public func scoutChoices() -> [Scout] {
        let done = Set(scouts.filter { $0.status == .completed || $0.status == .postponed }.map(\.id))
        var byID: [String: Scout] = [:]
        for youth in scheduledScouts + scouts where !youth.last.isEmpty && !done.contains(youth.id) {
            byID[youth.id] = youth
        }
        return byID.values.filter { $0.boardType != .projectReview }.sorted {
            ($0.last.lowercased(), $0.first.lowercased()) < ($1.last.lowercased(), $1.first.lowercased())
        }
    }

    // MARK: - Signing in

    /// A youth signs in at the check-in station.
    ///
    /// Signing in again updates the sign-in fields and nothing else, so it
    /// cannot move a youth's board along or change their result. A youth who
    /// matches a pre-registration (by ID or email) gets a `P` number, anyone
    /// else a `W` for walk-in; the number counts sign-ins within that group.
    ///
    /// - Parameter form: the check-in form's answers by column name. Only
    ///   `Scout.signInColumns`, `BoardType`, and `ID` are read, each trimmed of
    ///   surrounding whitespace, and a missing key reads as empty. Any other
    ///   key is ignored. `BoardType` must name a board type for a youth with no
    ///   record at this event yet; for one already signed in, it is not
    ///   checked.
    /// - Returns: the event's record for the youth after this sign-in.
    /// - Throws: `EventError` when the first or last name is blank ("Please
    ///   enter a first and last name."), when a youth with no record yet has
    ///   no valid board type ("Please choose Final Board or Proposal
    ///   Review."), or when `scouts.csv` cannot be written.
    @discardableResult
    public func registerYouth(_ form: [String: String]) throws -> Scout {
        var incoming = Scout.blank(at: now)
        for column in Scout.signInColumns + ["BoardType", "ID"] {
            incoming[column] = (form[column] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !incoming.first.isEmpty, !incoming.last.isEmpty else {
            throw EventError("Please enter a first and last name.")
        }
        incoming.assignIDIfNeeded()
        incoming.refreshDerivedFields()

        let preRegistered =
            scheduledScouts.contains { $0.id == incoming.id }
            || scheduledYouth(matchingEmail: incoming.email) != nil
        let nextRegNum =
            preRegistered
            ? "P\(scouts.filter(\.isPreRegistered).count + 1)"
            : "W\(scouts.filter(\.isWalkIn).count + 1)"

        let registered: Scout
        if let index = scouts.firstIndex(where: { $0.id == incoming.id }) {
            scouts[index].update(from: incoming, columns: Scout.signInColumns)
            if scouts[index].statusText.isEmpty {
                scouts[index].status = .registered
            }
            if scouts[index].regNum.isEmpty {
                scouts[index].regNum = nextRegNum
            }
            registered = scouts[index]
        } else {
            guard incoming.boardType != nil else {
                throw EventError("Please choose Final Board or Proposal Review.")
            }
            incoming.status = .registered
            incoming.regNum = nextRegNum
            scouts.append(incoming)
            registered = incoming
        }
        try save(.youth)
        return registered
    }

    /// An adult signs in at the check-in station.
    ///
    /// The event's record is created or updated, and so is the adult's permanent
    /// history record, which gains today's date. Signing in again does not
    /// take them off a board they are already sitting on.
    ///
    /// - Parameter form: the check-in form's answers by column name. Only
    ///   `Adult.signInColumns` and `ID` are read for the record, each trimmed
    ///   of surrounding whitespace, and a missing key reads as empty. A
    ///   `ProjectReview` or `FinalBoard` value that is not a `BoardRole` is
    ///   treated as blank, so it cannot overwrite a role already on file.
    ///   `WoodBadge` counts only when it is `Y`; `Supporting` holds the IDs of
    ///   the youth the adult came to introduce.
    /// - Returns: the event's record for the adult after this sign-in. Its
    ///   `flags` is `P` when the adult history already had them and `W` when
    ///   this sign-in added them to it.
    /// - Throws: `EventError` when the first or last name is blank ("Please
    ///   enter a first and last name."), or when `adults.csv` or the adult
    ///   history cannot be written.
    @discardableResult
    public func registerAdult(_ form: [String: String]) throws -> Adult {
        var incoming = Adult.blank(at: now)
        for column in Adult.signInColumns + ["ID"] {
            incoming[column] = (form[column] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !incoming.first.isEmpty, !incoming.last.isEmpty else {
            throw EventError("Please enter a first and last name.")
        }
        // A role that is missing or not a role is left blank here, so it
        // cannot overwrite one already on file; blanks are filled below.
        let roleColumns = ["ProjectReview", "FinalBoard"]
        for column in roleColumns where BoardRole(rawValue: incoming[column]) == nil {
            incoming[column] = ""
        }
        if let type = UnitType(rawValue: incoming.unitType), !type.hasUnitNumber {
            incoming.unit = ""
        }
        incoming.assignIDIfNeeded()
        incoming.refreshDerivedFields()
        // Answers for this event only. Anything but "Y" is no.
        incoming.woodBadge = form["WoodBadge"] == "Y" ? "Y" : ""
        incoming.supporting = (form["Supporting"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var record: Adult
        let eventIndex: Int
        if let index = adults.firstIndex(where: { $0.id == incoming.id }) {
            adults[index].update(from: incoming, columns: Adult.signInColumns)
            // The latest sign-in says what is true now.
            adults[index].woodBadge = incoming.woodBadge
            adults[index].supporting = incoming.supporting
            eventIndex = index
        } else {
            adults.append(incoming)
            eventIndex = adults.count - 1
        }
        record = adults[eventIndex]

        // Still no role: whatever the history says, or Member.
        let historyMatch = adultHistory.firstIndex(where: { $0.id == record.id })
        for column in roleColumns where record[column].isEmpty {
            let known = historyMatch.map { adultHistory[$0][column] } ?? ""
            record[column] = BoardRole(rawValue: known) != nil ? known : BoardRole.member.rawValue
        }

        let dayMark = "(\(Timestamp.dayStamp(for: now)))"
        if let historyIndex = historyMatch {
            adultHistory[historyIndex].update(from: record, columns: Adult.signInColumns)
            record.flags = "P"
            if !adultHistory[historyIndex].boardHistory.hasSuffix(dayMark) {
                adultHistory[historyIndex].boardHistory += dayMark
            }
        } else {
            var history = record
            history.regTime = Timestamp.recordStamp(for: now)
            history.room = ""
            history.flags = ""
            history["Sel"] = ""
            // The history pre-fills next month's form; whom someone came to
            // support, and whether it counted toward Wood Badge, are for
            // this event only.
            history.woodBadge = ""
            history.supporting = ""
            history.boardHistory += dayMark
            adultHistory.append(history)
            record.flags = "W"
        }
        adults[eventIndex] = record
        try save(.adults, .adultHistory)
        return record
    }

    // MARK: - The board lifecycle

    /// Convene a board: the members get the room and the paperwork, and the
    /// youth waits outside until Start Review.
    ///
    /// This is the hard backstop for the composition rules. The Seat Board
    /// sheet explains them first, but a request that skipped the sheet must
    /// still be refused here.
    ///
    /// - Parameters:
    ///   - roomID: the ID of a free room.
    ///   - scoutID: the ID of a youth who is waiting (Registered or Verified)
    ///     and holds no room other than this one.
    ///   - chairID: the ID of the adult who chairs. The adult must be among
    ///     `memberIDs` and qualified to chair this youth's board type.
    ///   - memberIDs: the IDs of the adults on the board. Blank entries and
    ///     repeats are dropped before counting. The count must reach
    ///     `BoardRules.minimumMembers(for:)` for the board type and stay within
    ///     `BoardRules.boardMaximum` (Guide to Advancement 8.0.0.3).
    /// - Throws: `EventError` when the room or youth is unknown; when the room
    ///   already has a board; when the youth is not waiting, is assigned to
    ///   another room, or has no board type; or when the board fails the
    ///   composition checks: no members, an unknown adult, one who has gone
    ///   home, one on another board, or one who said no thanks to this board
    ///   type; no member from outside the youth's unit; too few or too many
    ///   members; a chair who is blank, unknown, not among the members, or not
    ///   qualified for this board type. Also thrown when `scouts.csv`,
    ///   `rooms.csv`, or `adults.csv` cannot be written.
    public func seatBoard(roomID: String, scoutID: String, chairID: String, memberIDs: [String]) throws {
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }) else {
            throw EventError("There is no room '\(roomID)'.")
        }
        let room = rooms[roomIndex]
        guard room.isFree else {
            throw EventError(Self.roomIsTaken(room))
        }
        guard let scoutIndex = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        var scout = scouts[scoutIndex]
        guard scout.status?.isWaitingForBoard == true else {
            throw EventError("\(scout.shownFullName) cannot be seated from status '\(scout.statusLabel)'.")
        }
        // disabledForTodayMarker ("N/A") is what Complete leaves in a youth's
        // room. A Registered youth holding it had a result recorded against them
        // by mistake and was set back on the Youth page: they have no room
        // and must be seatable for their real board.
        guard scout.room.isEmpty || scout.room == disabledForTodayMarker || scout.room == room.name else {
            throw EventError("\(scout.shownFullName) is already assigned to room \(scout.room).")
        }
        guard let boardType = scout.boardType else {
            throw EventError("\(scout.shownFullName) has no board type.")
        }
        let (members, chair) = try checkedBoard(
            for: scout, boardType: boardType, chairID: chairID, memberIDs: memberIDs, sittingIn: nil)
        let uniqueMemberIDs = members.map(\.id)

        let memberNames = members.map(\.fullName).joined(separator: ",")
        rooms[roomIndex].scoutName = scout.fullName
        rooms[roomIndex].leaderNames = memberNames
        scout.room = room.name
        scout.status = .seated
        scout.boardMembers = memberNames
        scout.boardMemberIDs = uniqueMemberIDs.joined(separator: ",")
        scout.boardChair = chair.fullName
        scout.boardChairID = chair.id
        scout.markUpdated(at: now)
        scouts[scoutIndex] = scout
        for index in adults.indices where uniqueMemberIDs.contains(adults[index].id) {
            adults[index].room = room.name
        }
        try save(.youth, .rooms, .adults)
    }

    /// Change who sits on a board that is already Seated or InProgress: the
    /// same composition checks as `seatBoard`, the room stays the one the
    /// board already holds, and a member taken off is freed. The room timer
    /// is left running -- this corrects the board already convening or in
    /// review, not a new step in its lifecycle.
    ///
    /// - Parameters:
    ///   - scoutID: the ID of the youth whose board is Seated or InProgress.
    ///   - chairID: the ID of the adult who chairs, among `memberIDs` and
    ///     qualified for the board type.
    ///   - memberIDs: the IDs of the adults who would be on the board. Blank
    ///     entries and repeats are dropped before counting, and the count is
    ///     held to the same limits as in `seatBoard`. Members already on this
    ///     board are not refused for sitting in its room.
    /// - Throws: `EventError` when the youth is unknown, is not Seated or
    ///   InProgress, has no board type, or holds a room that is not on the
    ///   room list ("Room ... was not found."); when the new board fails the
    ///   composition checks listed under `seatBoard`, worded as what "would be
    ///   left"; or when `scouts.csv`, `rooms.csv`, or `adults.csv` cannot be
    ///   written.
    public func changeMembers(scoutID: String, chairID: String, memberIDs: [String]) throws {
        guard let scoutIndex = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        var scout = scouts[scoutIndex]
        guard scout.status == .seated || scout.status == .inProgress else {
            throw EventError(
                "\(scout.shownFullName)'s board members can only be changed while seated or in review (status '\(scout.statusLabel)')."
            )
        }
        guard let roomIndex = rooms.firstIndex(where: { $0.name == scout.room }) else {
            throw EventError("Room \(scout.room) was not found.")
        }
        guard let boardType = scout.boardType else {
            throw EventError("\(scout.shownFullName) has no board type.")
        }
        let (members, chair) = try checkedBoard(
            for: scout, boardType: boardType, chairID: chairID, memberIDs: memberIDs, sittingIn: scout.room)
        let uniqueMemberIDs = members.map(\.id)

        let leavingIDs = Set(scout.boardMembers(among: adults).members.map(\.id)).subtracting(uniqueMemberIDs)
        let memberNames = members.map(\.fullName).joined(separator: ",")
        rooms[roomIndex].leaderNames = memberNames
        scout.boardMembers = memberNames
        scout.boardMemberIDs = uniqueMemberIDs.joined(separator: ",")
        scout.boardChair = chair.fullName
        scout.boardChairID = chair.id
        scouts[scoutIndex] = scout
        for index in adults.indices where leavingIDs.contains(adults[index].id) {
            adults[index].room = ""
        }
        for index in adults.indices where uniqueMemberIDs.contains(adults[index].id) {
            adults[index].room = scout.room
        }
        try save(.youth, .rooms, .adults)
    }

    /// Who is on a board and who chairs it, checked the same way for a new
    /// board and for one already sitting, whose room is `sittingIn`: its own
    /// members are not on another board, and the counts say what would be
    /// left. Duplicate IDs count once. The refusals use the screen's words
    /// (the board type as shown, "gone home", a count with no "(s)") and end
    /// with what to do, as Windows' `CheckComposition` does.
    ///
    /// - Parameters:
    ///   - scout: the youth the board is for.
    ///   - boardType: the kind of board, which sets the minimum size and which
    ///     adult roles count.
    ///   - chairID: the ID of the proposed chair.
    ///   - memberIDs: the IDs of the proposed members.
    ///   - currentRoom: the room the board already holds, or nil for a new
    ///     board.
    /// - Returns: the members and the chair as `Adult` records.
    /// - Throws: `EventError` for no members, an unknown adult, an adult who
    ///   has gone home, is on another board, or said no thanks to this board
    ///   type, no member from outside the youth's unit, a count below the
    ///   minimum or above `BoardRules.boardMaximum`, or a chair who is blank,
    ///   unknown, not among the members, or not qualified to chair the type.
    private func checkedBoard(
        for scout: Scout, boardType: BoardType, chairID: String, memberIDs: [String], sittingIn currentRoom: String?
    ) throws -> (members: [Adult], chair: Adult) {
        let label = boardType.label
        let minimum = BoardRules.minimumMembers(for: boardType)
        let changing = currentRoom != nil

        var seenIDs = Set<String>()
        let uniqueMemberIDs =
            memberIDs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seenIDs.insert($0).inserted }
        guard !uniqueMemberIDs.isEmpty else {
            throw EventError(
                changing
                    ? "No members would be left, and a \(label) needs at least \(minimum). Add \(minimum) before saving."
                    : "The board has no members yet. Add at least \(minimum) for a \(label).")
        }

        var members: [Adult] = []
        for memberID in uniqueMemberIDs {
            guard let member = adult(id: memberID) else {
                throw EventError("There is no adult '\(memberID)'.")
            }
            let name = member.shownFullName
            if member.isDisabledForToday {
                throw EventError(
                    "\(name) has gone home. Bring them back with Adult › Mark Back, or choose someone else.")
            }
            if !member.room.isEmpty && member.room != currentRoom {
                throw EventError("\(name) is on the board in room \(member.room). Choose someone else.")
            }
            // "No thanks" to this kind of board at sign-in is stored as
            // Unavailable for it; a hand-picked board must not seat them either.
            if member.role(for: boardType) == .unavailable {
                throw EventError("\(name) said no thanks to \(label)s. Choose someone else.")
            }
            members.append(member)
        }
        // The council's same-unit rule may be overridden; the national floor
        // of one member from outside the unit may not (SPEC.md D-4).
        guard BoardRules.hasMemberFromOutsideUnit(scoutUnitName: scout.unitName, members: members) else {
            throw EventError(
                BoardRules.noMemberFromOutsideUnit(scoutName: scout.shownFullName, scoutUnitName: scout.unitName))
        }

        let count = members.count
        let maximum = BoardRules.boardMaximum
        switch BoardRules.checkSize(count, for: boardType) {
        case .tooFew:
            let short = "a \(label) needs at least \(minimum). Add \(minimum - count) more"
            throw EventError(
                changing
                    ? "Only \(Count.of(count, "member", "members")) would be left, and \(short) before saving."
                    : "Only \(Count.of(count, "member", "members")) \(count == 1 ? "is" : "are") on the board, and \(short)."
            )
        case .tooMany:
            let limit =
                "a \(label) can have at most \(maximum) (Guide to Advancement 8.0.0.3). Remove \(count - maximum)"
            throw EventError(
                changing
                    ? "That would make \(count) members, and \(limit) before saving."
                    : "\(count) members are on the board, and \(limit).")
        case .ok, .overPreferred:
            break
        }

        // The Chair designation is binding. Promoting someone is a deliberate
        // edit on the Adults page, never a side effect of seating a board
        // because the qualified chairs were all busy.
        guard !chairID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw EventError("No one is chosen to chair the board. Choose which qualified member chairs it.")
        }
        guard let chair = adult(id: chairID) else {
            throw EventError("There is no adult '\(chairID)' to chair the board.")
        }
        guard uniqueMemberIDs.contains(chair.id) else {
            throw EventError(
                "\(chair.shownFullName) would chair the board but isn't one of its members. "
                    + "Add them to the board, or choose another chair.")
        }
        guard chair.canChair(boardType) else {
            throw EventError(
                "\(chair.shownFullName) isn't a chair for \(label)s. "
                    + "Choose a qualified chair, or make them a chair on the Adults page.")
        }
        return (members, chair)
    }

    /// Bring the youth into the room and begin the review.
    ///
    /// - Parameter scoutID: the ID of a youth whose board is Seated.
    /// - Throws: `EventError` when the youth is unknown or the board is not
    ///   Seated ("... board has not been seated"), or when `scouts.csv` cannot
    ///   be written.
    public func startReview(scoutID: String) throws {
        guard let index = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        guard scouts[index].status == .seated else {
            throw EventError(
                "\(scouts[index].shownFullName)'s board has not been seated (status '\(scouts[index].statusLabel)').")
        }
        scouts[index].status = .inProgress
        scouts[index].markUpdated(at: now)
        try save(.youth)
    }

    /// Record the result and hand the room and the members back.
    ///
    /// Only a review in progress can be completed. A Seated board has not
    /// seen the youth yet, and completing it would record a result for a
    /// review that never happened.
    ///
    /// - Parameters:
    ///   - scoutID: the ID of a youth whose review is InProgress.
    ///   - result: the board's decision, stored as its raw value.
    ///   - notes: the board's notes, stored as given.
    /// - Throws: `EventError` when the youth is unknown, the review has not
    ///   started ("... review has not started"), or the youth's room is not on
    ///   the room list ("Room ... was not found."); or when `scouts.csv`,
    ///   `rooms.csv`, or `adults.csv` cannot be written.
    public func completeBoard(scoutID: String, result: BoardResult, notes: String) throws {
        guard let scoutIndex = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        guard scouts[scoutIndex].status == .inProgress else {
            throw EventError(
                "\(scouts[scoutIndex].shownFullName)'s review has not started (status '\(scouts[scoutIndex].statusLabel)')."
            )
        }
        let roomName = scouts[scoutIndex].room
        guard let roomIndex = rooms.firstIndex(where: { $0.name == roomName }) else {
            throw EventError("Room \(roomName) was not found.")
        }
        releaseRoom(at: roomIndex)
        scouts[scoutIndex].status = .completed
        scouts[scoutIndex].room = disabledForTodayMarker
        scouts[scoutIndex].notes = notes
        scouts[scoutIndex].result = result.rawValue
        scouts[scoutIndex].markUpdated(at: now)
        try save(.youth, .rooms, .adults)
    }

    /// Put a waiting youth's board off to another event.
    ///
    /// - Parameter scoutID: the ID of a youth who is waiting (Registered or
    ///   Verified).
    /// - Throws: `EventError` when the youth is unknown or is not waiting
    ///   ("Only a youth still waiting can be postponed"), or when `scouts.csv`
    ///   cannot be written.
    public func postponeBoard(scoutID: String) throws {
        guard let index = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        guard scouts[index].status?.isWaitingForBoard == true else {
            throw EventError(
                "Only a youth still waiting can be postponed; \(scouts[index].shownFullName) is '\(scouts[index].statusLabel)'."
            )
        }
        scouts[index].status = .postponed
        scouts[index].markUpdated(at: now)
        try save(.youth)
    }

    /// Undo seating: the youth goes back to waiting, and the room and the
    /// members are free again.
    ///
    /// - Parameter scoutID: the ID of a youth whose status is Seated,
    ///   InProgress, or Verified.
    /// - Throws: `EventError` when the youth is unknown or has any other
    ///   status ("Only a seated board or one in review can be reset"), or when
    ///   `scouts.csv`, `rooms.csv`, or `adults.csv` cannot be written.
    public func resetBoard(scoutID: String) throws {
        guard let scoutIndex = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        let status = scouts[scoutIndex].status
        guard status == .seated || status == .inProgress || status == .verified else {
            throw EventError(
                "Only a seated board or one in review can be reset; \(scouts[scoutIndex].shownFullName) is '\(scouts[scoutIndex].statusLabel)'."
            )
        }
        if let roomIndex = rooms.firstIndex(where: { $0.name == scouts[scoutIndex].room }) {
            releaseRoom(at: roomIndex)
        }
        scouts[scoutIndex].status = .registered
        scouts[scoutIndex].room = ""
        scouts[scoutIndex].boardChair = ""
        scouts[scoutIndex].boardChairID = ""
        scouts[scoutIndex].boardMemberIDs = ""
        scouts[scoutIndex].boardMembers = ""
        scouts[scoutIndex].markUpdated(at: now)
        try save(.youth, .rooms, .adults)
    }

    /// Put a youth's board back the way it was before a step -- what Undo
    /// does after Seat Board, Start Review, Complete, Postpone or Reset. The
    /// board columns and the timer come back from `earlier`; anything else on
    /// the record (a leader corrected since) is left as it is now. The room
    /// and the members are taken back, or released, to match.
    ///
    /// Refused when the room or a member has been given to another board, or
    /// a member has gone home, since: the event has moved on, and undoing
    /// would put someone on two boards at once.
    ///
    /// - Parameter earlier: the youth's record as it stood before the step.
    ///   Its `id` picks the record to restore.
    /// - Throws: `EventError` when the youth is unknown. When `earlier` held a
    ///   room, also when that room is no longer on the list, has been given to
    ///   another board, or when a member on `earlier`'s board is unknown, has
    ///   gone home, or is on another board now. Each of those refusals ends
    ///   "Change the board by hand instead." Also thrown when `scouts.csv`,
    ///   `rooms.csv`, or `adults.csv` cannot be written.
    public func restoreBoard(_ earlier: Scout) throws {
        guard let scoutIndex = scouts.firstIndex(where: { $0.id == earlier.id }) else {
            throw EventError("There is no youth '\(earlier.id)'.")
        }
        let current = scouts[scoutIndex]
        let holdsRoom: (Scout) -> Bool = { $0.status?.holdsRoom == true }
        let currentRoom = holdsRoom(current) ? current.room : nil

        var roomIndex: Int?
        var memberIDs: [String] = []
        if holdsRoom(earlier) {
            guard let index = rooms.firstIndex(where: { $0.name == earlier.room }) else {
                throw EventError("Room \(earlier.room) is no longer on today's list. \(Self.byHandInstead)")
            }
            guard rooms[index].isFree || rooms[index].name == currentRoom else {
                throw EventError(
                    "Room \(earlier.room) has been given to \(rooms[index].scoutName.shownValue) since. \(Self.byHandInstead)"
                )
            }
            let listed = earlier.boardMembers(among: adults)
            guard listed.unknown.isEmpty else {
                throw EventError("There is no adult '\(listed.unknown)'.")
            }
            memberIDs = listed.members.map(\.id)
            for member in listed.members {
                if member.isDisabledForToday {
                    throw EventError("\(member.shownFullName) has gone home since. \(Self.byHandInstead)")
                }
                guard member.room.isEmpty || member.room == currentRoom else {
                    throw EventError(
                        "\(member.shownFullName) is on the board in room \(member.room) now. \(Self.byHandInstead)")
                }
            }
            roomIndex = index
        }

        if let currentRoom, let index = rooms.firstIndex(where: { $0.name == currentRoom }) {
            releaseRoom(at: index)
        }
        var restored = current
        restored.statusText = earlier.statusText
        restored.room = earlier.room
        restored.boardChair = earlier.boardChair
        restored.boardChairID = earlier.boardChairID
        restored.boardMembers = earlier.boardMembers
        restored.boardMemberIDs = earlier.boardMemberIDs
        restored.result = earlier.result
        restored.notes = earlier.notes
        restored.lastUpdateTime = earlier.lastUpdateTime
        scouts[scoutIndex] = restored
        if let roomIndex {
            rooms[roomIndex].scoutName = restored.fullName
            rooms[roomIndex].leaderNames = restored.boardMembers
            for index in adults.indices where memberIDs.contains(adults[index].id) {
                adults[index].room = restored.room
            }
        }
        try save(.youth, .rooms, .adults)
    }

    /// How a refused Undo or Redo of a board step ends: what changed is said
    /// first, and the same words serve both directions.
    private static let byHandInstead = "Change the board by hand instead."

    private func releaseRoom(at roomIndex: Int) {
        let roomName = rooms[roomIndex].name
        for index in adults.indices where adults[index].room == roomName {
            adults[index].room = ""
        }
        rooms[roomIndex].scoutName = ""
        rooms[roomIndex].leaderNames = ""
    }

    // MARK: - Rooms

    /// A room's ID is `ROOM:<name>` when it is made, and it stays that when
    /// the room is renamed, as in the Java and Windows versions (Java event
    /// test section 23): a rooms file either one wrote can hold ROOM:101
    /// under the name 110. So rooms are told apart by name, and a new room
    /// takes the next ID that is free, `ROOM:101-2` while ROOM:101 is taken.
    private func nextFreeRoomID(for name: String) -> Room.ID {
        let plain = Room.roomID(for: name)
        guard room(id: plain) != nil else { return plain }
        var number = 2
        while room(id: "\(plain)-\(number)") != nil {
            number += 1
        }
        return "\(plain)-\(number)"
    }

    /// A room name as typed, trimmed, or the reason it cannot be used.
    /// `excludedID` is the room being renamed, which may keep its own name.
    ///
    /// - Throws: `EventError` when the trimmed name is empty, contains a
    ///   comma, equals `disabledForTodayMarker` in any letter case, or is
    ///   already another room's name.
    private func checkedRoomName(_ rawName: String, excluding excludedID: Room.ID? = nil) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw EventError("Enter a room name.")
        }
        guard !name.contains(",") else {
            throw EventError("A room name can't contain a comma. Leave the comma out.")
        }
        // An adult's room holds this marker when they have gone home, so a
        // room by that name would look like it held every one of them.
        guard name.caseInsensitiveCompare(disabledForTodayMarker) != .orderedSame else {
            throw EventError("\(disabledForTodayMarker) marks adults who have gone home. Choose another name.")
        }
        guard !rooms.contains(where: { $0.name == name && $0.id != excludedID }) else {
            throw EventError("There's already a room \(name). Choose another name.")
        }
        return name
    }

    /// Add an empty room to the event's list, for one kind of board.
    ///
    /// - Parameters:
    ///   - rawName: the room's name as typed. It is trimmed, and must not be
    ///     empty, contain a comma, equal `disabledForTodayMarker` in any
    ///     letter case, or match another room's name.
    ///   - boardType: the kind of board the room is used for.
    /// - Returns: the new room's ID, `ROOM:<name>`, with a `-2` or higher
    ///   suffix when that ID is already taken.
    /// - Throws: `EventError` for a name that breaks one of those rules, or
    ///   when `rooms.csv` cannot be written.
    @discardableResult
    public func addRoom(named rawName: String, boardType: BoardType) throws -> Room.ID {
        let name = try checkedRoomName(rawName)
        var newRoom = Room.blank(at: now)
        newRoom["ID"] = nextFreeRoomID(for: name)
        newRoom.name = name
        newRoom.boardTypeText = boardType.rawValue
        rooms.append(newRoom)
        try save(.rooms)
        return newRoom.id
    }

    /// Put back a room that was removed, with its own ID, name and use: what
    /// Undo of Remove Room and Redo of Add Room do. Refused when another room
    /// has that ID or that name since.
    ///
    /// - Parameter room: the room as it was removed, with its own ID, name,
    ///   and board type.
    /// - Throws: `EventError` when another room has `room`'s name ("There's
    ///   already a room ...") or its ID ("... has taken its place since"), or
    ///   when `rooms.csv` cannot be written.
    public func restoreRoom(_ room: Room) throws {
        guard self.room(named: room.name) == nil else {
            throw EventError("There's already a room \(room.name). Rename or remove it first.")
        }
        if let other = self.room(id: room.id) {
            throw EventError("Room \(other.name) has taken its place since. Add room \(room.name) by hand instead.")
        }
        rooms.append(room)
        try save(.rooms)
    }

    /// Why a room with a board in it cannot be removed, the same in the
    /// Room menu's alert and in `removeRoom`'s refusal.
    public static func roomHasABoard(_ roomName: String) -> String {
        "Room \(roomName) has a board in it. Complete, reset, or move that board first."
    }

    /// Why a youth cannot be seated in a room another board holds, the same
    /// in the seating review, in `seatBoard`'s refusal, and for a youth
    /// dropped on the room's card. Nonisolated for the review, which is not
    /// tied to the main actor.
    public nonisolated static func roomIsTaken(_ room: Room) -> String {
        "Room \(room.name) already has \(room.scoutName.shownValue)'s board. Choose a free room."
    }

    /// Remove a room that has no board in it.
    ///
    /// - Parameter id: the ID of the room to remove.
    /// - Throws: `EventError` when the id is unknown or a board holds the room,
    ///   or when `rooms.csv` cannot be written.
    public func removeRoom(id: String) throws {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else {
            throw EventError("There is no room '\(id)'.")
        }
        guard rooms[index].isFree else {
            throw EventError(Self.roomHasABoard(rooms[index].name))
        }
        rooms.remove(at: index)
        try save(.rooms)
    }

    /// Rename a room, for example when the building signs it differently
    /// than the list says. The room keeps its ID. A board sitting in it goes
    /// along: the youth and the adults hold the room by name, and a rename
    /// that left them on the old one would strand the members on a room that
    /// no longer exists, the Java app's failure when its Admin page renamed
    /// a room under a board. The board's timer is not restarted; renaming is
    /// not a step in its review.
    ///
    /// - Parameters:
    ///   - id: the ID of the room to rename.
    ///   - rawName: the new name as typed. It is trimmed and held to the rules
    ///     under `addRoom`, except that the room may keep its own name. A name
    ///     equal to the current one changes nothing and does not throw.
    /// - Throws: `EventError` when the id is unknown, the name breaks one of
    ///   those rules, or `rooms.csv`, `scouts.csv`, or `adults.csv` cannot be
    ///   written.
    public func renameRoom(id: String, to rawName: String) throws {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else {
            throw EventError("There is no room '\(id)'.")
        }
        let oldName = rooms[index].name
        guard rawName.trimmingCharacters(in: .whitespacesAndNewlines) != oldName else {
            return
        }
        let newName = try checkedRoomName(rawName, excluding: id)
        rooms[index].name = newName
        for scoutIndex in scouts.indices where scouts[scoutIndex].room == oldName {
            scouts[scoutIndex].room = newName
        }
        for adultIndex in adults.indices where adults[adultIndex].room == oldName {
            adults[adultIndex].room = newName
        }
        try save(.rooms, .youth, .adults)
    }

    /// Change which kind of board the room is used for. A board already in
    /// the room keeps its own type.
    ///
    /// - Parameters:
    ///   - boardType: the kind of board the room is used for from now on.
    ///   - id: the ID of the room.
    /// - Throws: `EventError` when the id is unknown, or when `rooms.csv`
    ///   cannot be written.
    public func setBoardType(_ boardType: BoardType, forRoom id: String) throws {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else {
            throw EventError("There is no room '\(id)'.")
        }
        rooms[index].boardTypeText = boardType.rawValue
        try save(.rooms)
    }

    /// Swap everything between two rooms: the youth, the members and the
    /// names on the cards. Either room may be empty, which makes this a move.
    ///
    /// - Parameters:
    ///   - firstID: the ID of one room.
    ///   - secondID: the ID of the other room, which must differ from `firstID`.
    /// - Throws: `EventError` when the two IDs are the same ("Pick two
    ///   different rooms."), when either is unknown, when either room is
    ///   assigned to more than one youth, or when `rooms.csv`, `scouts.csv`,
    ///   or `adults.csv` cannot be written.
    public func swapRooms(_ firstID: String, _ secondID: String) throws {
        guard firstID != secondID else {
            throw EventError("Pick two different rooms.")
        }
        guard let firstIndex = rooms.firstIndex(where: { $0.id == firstID }) else {
            throw EventError("There is no room '\(firstID)'.")
        }
        guard let secondIndex = rooms.firstIndex(where: { $0.id == secondID }) else {
            throw EventError("There is no room '\(secondID)'.")
        }
        let firstName = rooms[firstIndex].name
        let secondName = rooms[secondIndex].name
        let youthInFirst = scouts.indices.filter { scouts[$0].room == firstName }
        let youthInSecond = scouts.indices.filter { scouts[$0].room == secondName }
        guard youthInFirst.count <= 1 else {
            throw EventError("Room \(firstName) is assigned to more than one youth.")
        }
        guard youthInSecond.count <= 1 else {
            throw EventError("Room \(secondName) is assigned to more than one youth.")
        }
        let adultsInFirst = adults.indices.filter { adults[$0].room == firstName }
        let adultsInSecond = adults.indices.filter { adults[$0].room == secondName }

        let firstCard = (rooms[firstIndex].scoutName, rooms[firstIndex].leaderNames)
        rooms[firstIndex].scoutName = rooms[secondIndex].scoutName
        rooms[firstIndex].leaderNames = rooms[secondIndex].leaderNames
        rooms[secondIndex].scoutName = firstCard.0
        rooms[secondIndex].leaderNames = firstCard.1
        for index in youthInFirst { scouts[index].room = secondName }
        for index in youthInSecond { scouts[index].room = firstName }
        for index in adultsInFirst { adults[index].room = secondName }
        for index in adultsInSecond { adults[index].room = firstName }
        try save(.rooms, .youth, .adults)
    }

    /// Add the rooms from an earlier event that this event does not have yet
    /// (by name), empty, so the room list does not have to be typed in every
    /// month.
    ///
    /// Each room added keeps its board type from the earlier event. A room
    /// with no name in the earlier list is skipped.
    ///
    /// - Parameter earlierEvent: the date of the earlier event, `YYYY-MM-DD`,
    ///   whose folder holds the rooms file to read. A folder with no rooms
    ///   file adds nothing.
    /// - Returns: the IDs of the rooms added, in the earlier event's order, for
    ///   Undo to remove.
    /// - Throws: the Foundation error when the earlier event's rooms file
    ///   exists but cannot be read, and `EventError` when `rooms.csv` cannot
    ///   be written.
    @discardableResult
    public func copyRooms(fromEvent earlierEvent: String) throws -> [Room.ID] {
        let earlierRooms = try CSVFile.read(Room.self, from: folder.roomsURL(event: earlierEvent))
        var added: [Room.ID] = []
        for earlier in earlierRooms where !earlier.name.isEmpty && room(named: earlier.name) == nil {
            var copy = Room.blank(at: now)
            copy["ID"] = nextFreeRoomID(for: earlier.name)
            copy.name = earlier.name
            copy.boardTypeText = earlier.boardTypeText
            rooms.append(copy)
            added.append(copy.id)
        }
        if !added.isEmpty {
            try save(.rooms)
        }
        return added
    }

    // MARK: - Adults

    /// Mark Back or Mark Gone Home: bring an adult back, or stand them down
    /// for the event.
    ///
    /// - Parameters:
    ///   - available: `true` brings the adult back, which needs them marked
    ///     gone home; `false` marks them gone home, which needs them off any
    ///     board.
    ///   - adultID: the ID of the adult.
    /// - Throws: `EventError` when the adult is unknown, is not marked gone
    ///   home and `available` is `true`, is already marked gone home and
    ///   `available` is `false`, or is on a board and `available` is `false`;
    ///   or when `adults.csv` cannot be written.
    public func setAvailable(_ available: Bool, adultID: String) throws {
        guard let index = adults.firstIndex(where: { $0.id == adultID }) else {
            throw EventError("There is no adult '\(adultID)'.")
        }
        let adult = adults[index]
        if available {
            guard adult.isDisabledForToday else {
                throw EventError("\(adult.shownFullName) isn't marked gone home.")
            }
            adults[index].room = ""
        } else {
            if adult.isDisabledForToday {
                throw EventError("\(adult.shownFullName) is already marked gone home.")
            }
            guard adult.room.isEmpty else {
                throw EventError(Self.onABoard(adult))
            }
            adults[index].room = disabledForTodayMarker
        }
        try save(.adults)
    }

    /// Why an adult on a board cannot be marked gone home or deleted, and
    /// the way out.
    private static func onABoard(_ adult: Adult) -> String {
        "\(adult.shownFullName) is on the board in room \(adult.room). "
            + "Take them off it with Board › Change Members… first, or reset or complete that board."
    }

    /// Link an adult to a youth as the one who introduces them (SPEC.md D-23), or
    /// unlink them after sign-in, for the adult who did not
    /// check the youth at sign-in. Writes the same Supporting column. Linking
    /// needs a youth who is signed in or RSVP'd; clearing a stale link does not.
    ///
    /// - Parameters:
    ///   - linked: `true` links the adult to the youth, `false` unlinks them.
    ///   - adultID: the ID of the adult at this event.
    ///   - scoutID: the ID of the youth.
    /// - Throws: `EventError` when the adult is unknown, when `linked` is
    ///   `true` and the youth is neither signed in nor pre-registered, or when
    ///   `adults.csv` cannot be written.
    public func setSupporting(_ linked: Bool, adultID: String, scoutID: String) throws {
        guard let index = adults.firstIndex(where: { $0.id == adultID }) else {
            throw EventError("There is no adult '\(adultID)'.")
        }
        if linked && scout(id: scoutID) == nil && !scheduledScouts.contains(where: { $0.id == scoutID }) {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        adults[index].supporting = Adult.withSupportLink(adults[index].supporting, scoutID, linked: linked)
        try save(.adults)
    }

    // MARK: - Editing records directly

    /// Replace a youth record as edited on the Results, Youth or
    /// Pre-Registered page.
    ///
    /// The pages show a youth's status read-only: it changes through the Event
    /// page's steps, which give the youth a room and members and take them
    /// back (SPEC.md P-6). A record can still be set back to Registered, or to
    /// Completed or Postponed, to move a result recorded against the wrong
    /// youth (Java event test section 18), but never to Seated or In review,
    /// and a board that is sitting keeps its status until Reset or Complete
    /// (section 25).
    ///
    /// - Parameters:
    ///   - edited: the youth's record with the changes made. Its `id` picks the
    ///     record it replaces.
    ///   - scheduled: `true` replaces a pre-registration, which skips the
    ///     status checks, and `false` replaces a youth who has signed in.
    /// - Throws: `EventError` when no such record exists ("That
    ///   pre-registration no longer exists." or "That youth no longer
    ///   exists."). For a youth who has signed in, also when the status would
    ///   change to Seated or In review, or when it would change for a youth
    ///   whose board holds a room. Also thrown when `scouts_scheduled.csv` or
    ///   `scouts.csv` cannot be written.
    public func updateYouth(_ edited: Scout, scheduled: Bool = false) throws {
        var record = edited
        record.refreshDerivedFields()
        if scheduled {
            guard let index = scheduledScouts.firstIndex(where: { $0.id == edited.id }) else {
                throw EventError("That pre-registration no longer exists.")
            }
            scheduledScouts[index] = record
            try save(.scheduledYouth)
        } else {
            guard let index = scouts.firstIndex(where: { $0.id == edited.id }) else {
                throw EventError("That youth no longer exists.")
            }
            let current = scouts[index]
            if record.statusText != current.statusText {
                if record.status?.holdsRoom == true {
                    throw EventError(
                        "\(current.shownFullName) can be seated, or their review started, only on the Event page, "
                            + "where the board gets its room and members.")
                }
                if current.status?.holdsRoom == true {
                    throw EventError(
                        "\(current.shownFullName)'s board is in room \(current.room). Reset it or complete it on the "
                            + "Event page, which frees the room and its members.")
                }
            }
            scouts[index] = record
            try save(.youth)
        }
    }

    /// Delete a youth's row. An id nobody has changes nothing.
    ///
    /// - Parameters:
    ///   - id: the youth's id.
    ///   - scheduled: `true` deletes from the pre-registered table, where no
    ///     board can be sitting, so the active-board check is skipped.
    /// - Throws: `EventError` when the youth is seated or in review, so the
    ///   board must be reset or completed first, or when the youth file
    ///   cannot be written.
    public func deleteYouth(id: String, scheduled: Bool = false) throws {
        if scheduled {
            scheduledScouts.removeAll { $0.id == id }
            try save(.scheduledYouth)
        } else {
            if let scout = scout(id: id), scout.status?.holdsRoom == true {
                throw EventError(
                    "\(scout.shownFullName)'s board is active in room \(scout.room). Reset or complete that board first."
                )
            }
            scouts.removeAll { $0.id == id }
            try save(.youth)
        }
    }

    /// Replace one of the event's adults as edited on the Adults page.
    ///
    /// An adult's name, unit, contact and roles (`Adult.signInColumns`) are
    /// one set of facts in the event's adults and the adult history, as a
    /// sign-in carries them between the two tables (SPEC.md P-6): the change
    /// is made to the same adult in the history too, so someone promoted to
    /// Chair today is a chair the next time they sign in. Wood Badge, whom
    /// they introduce and their room belong to this event alone. The
    /// history itself is read-only: a sign-in writes it, and this reaches it.
    ///
    /// - Parameter edited: the adult's record with the changes made. Its `id`
    ///   picks the record it replaces.
    /// - Throws: `EventError` when the event has no such adult ("That adult no
    ///   longer exists."), or when `adults.csv` or the adult history cannot be
    ///   written.
    public func updateAdult(_ edited: Adult) throws {
        var record = edited
        record.refreshDerivedFields()
        guard let eventIndex = adults.firstIndex(where: { $0.id == edited.id }) else {
            throw EventError("That adult no longer exists.")
        }
        adults[eventIndex] = record
        if let historyIndex = adultHistory.firstIndex(where: { $0.id == edited.id }) {
            adultHistory[historyIndex].copyFacts(from: record)
        }
        try save(.adults, .adultHistory)
    }

    /// Take an adult off the event's list. The adult history keeps them. An id
    /// nobody has changes nothing.
    ///
    /// - Parameter id: the ID of the adult.
    /// - Throws: `EventError` when the adult is on a board, which must be
    ///   changed, reset, or completed first, or when `adults.csv` cannot be
    ///   written.
    public func deleteAdult(id: String) throws {
        if let adult = adult(id: id), adult.isOnBoard {
            throw EventError(Self.onABoard(adult))
        }
        adults.removeAll { $0.id == id }
        try save(.adults)
    }

    /// Replace the event's settings with `edited`'s. A blank value falls back
    /// to the standard one, as `Config(fields:)` merges over `Config.defaults`.
    ///
    /// - Parameter edited: the settings with the changes made.
    /// - Throws: `EventError` when `config.properties` cannot be written.
    public func updateConfig(_ edited: Config) throws {
        config = Config(fields: edited.fields)
        try save(.config)
    }

    // MARK: - SignUpGenius

    /// How many SignUpGenius entries `mergeSignUps` did each thing with. Every
    /// entry falls under at most one count, and an entry the import did not
    /// recognize as an adult slot is treated as a youth.
    public struct SignUpImportSummary: Sendable, Equatable {
        /// Adults with no history record under their email, added to the
        /// adult history as Members for both board types.
        public var addedAdults = 0
        /// Adults whose email matched exactly one history record. Counted
        /// whether or not the entry carried a phone number to update.
        public var updatedAdults = 0
        /// Adults left alone because their email matched more than one history
        /// record.
        public var skippedDuplicateAdults = 0
        /// Youth added to the event's pre-registrations.
        public var addedYouth = 0
        /// Youth left alone because a pre-registration already has their
        /// email.
        public var alreadyScheduledYouth = 0
        /// Entries, adult or youth, whose date does not fall in the month
        /// being imported.
        public var outsideThisMonth = 0

        /// Creates a summary; every count starts at zero.
        public init(
            addedAdults: Int = 0, updatedAdults: Int = 0, skippedDuplicateAdults: Int = 0,
            addedYouth: Int = 0, alreadyScheduledYouth: Int = 0, outsideThisMonth: Int = 0
        ) {
            self.addedAdults = addedAdults
            self.updatedAdults = updatedAdults
            self.skippedDuplicateAdults = skippedDuplicateAdults
            self.addedYouth = addedYouth
            self.alreadyScheduledYouth = alreadyScheduledYouth
            self.outsideThisMonth = outsideThisMonth
        }

        /// What the import reports, in words: a line for youth (added, and how
        /// many were already pre-registered), a line for adults (added to the
        /// history, and updated), and a third line only when some adults were
        /// skipped because their email is on more than one history record.
        /// `outsideThisMonth` is not reported.
        public var report: String {
            var lines = [
                "\(addedYouth) youth pre-registered, \(alreadyScheduledYouth) already \(alreadyScheduledYouth == 1 ? "was" : "were").",
                "\(Count.of(addedAdults, "adult", "adults")) added to the history, \(updatedAdults) updated.",
            ]
            if skippedDuplicateAdults > 0 {
                lines.append("\(skippedDuplicateAdults) skipped: their email is on more than one history record.")
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Merge SignUpGenius sign-ups into the adult history and the event's
    /// pre-registrations.
    ///
    /// Only entries dated in `month` (`YYYY-MM`) are used -- by calendar month,
    /// as the Java app did, so two board events in one month both import. An
    /// adult is matched to the history by email: one match gets their phone
    /// updated, none adds them as a Member for both board types, and more than
    /// one is left alone rather than guessed at. A youth is pre-registered
    /// unless a pre-registration already has their email.
    ///
    /// - Parameters:
    ///   - entries: the SignUpGenius sign-ups to merge.
    ///   - month: the month to import, `YYYY-MM`. An entry is used when its
    ///     start date begins with this text; nothing here checks the format.
    /// - Returns: how many entries were added, updated, skipped, or left out
    ///   for another month.
    /// - Throws: `EventError` when the adult history or `scouts_scheduled.csv`
    ///   cannot be written.
    @discardableResult
    public func mergeSignUps(_ entries: [SignUpEntry], month: String) throws -> SignUpImportSummary {
        var summary = SignUpImportSummary()
        for entry in entries {
            guard entry.startDate.hasPrefix(month) else {
                summary.outsideThisMonth += 1
                continue
            }
            let unit = NameCleanup.unit(from: entry.unitText)
            if entry.isAdultSlot {
                let matches = adultHistory.indices.filter {
                    Self.matchableEmail(adultHistory[$0].email) != nil
                        && Self.matchableEmail(adultHistory[$0].email) == Self.matchableEmail(entry.email)
                }
                if matches.count == 1 {
                    let phone = NameCleanup.phone(entry.phoneText)
                    if !phone.isEmpty {
                        adultHistory[matches[0]].phone = phone
                    }
                    summary.updatedAdults += 1
                } else if matches.count > 1 {
                    summary.skippedDuplicateAdults += 1
                } else {
                    var adult = Adult.blank(at: now)
                    adult.first = NameCleanup.name(entry.firstName)
                    adult.last = NameCleanup.name(entry.lastName)
                    adult.email = entry.email.trimmingCharacters(in: .whitespaces)
                    adult.phone = NameCleanup.phone(entry.phoneText)
                    adult.unitType = unit.type.rawValue
                    adult.unit = unit.number
                    adult.projectReviewRoleText = BoardRole.member.rawValue
                    adult.finalBoardRoleText = BoardRole.member.rawValue
                    adult.assignIDIfNeeded()
                    adult.refreshDerivedFields()
                    adultHistory.append(adult)
                    summary.addedAdults += 1
                }
            } else {
                if scheduledScouts.contains(where: {
                    Self.matchableEmail($0.email) != nil
                        && Self.matchableEmail($0.email) == Self.matchableEmail(entry.email)
                }) {
                    summary.alreadyScheduledYouth += 1
                    continue
                }
                var youth = Scout.blank(at: now)
                youth.first = NameCleanup.name(entry.firstName)
                youth.last = NameCleanup.name(entry.lastName)
                youth.email = entry.email.trimmingCharacters(in: .whitespaces)
                // No phone number: nothing uses a youth's (SPEC.md D-8).
                youth.unitType = unit.type.rawValue
                youth.unit = unit.number
                youth.leader = NameCleanup.leader(entry.leaderText)
                youth.boardTypeText = NameCleanup.boardType(fromSlot: entry.item)?.rawValue ?? ""
                youth.assignIDIfNeeded()
                youth.refreshDerivedFields()
                scheduledScouts.append(youth)
                summary.addedYouth += 1
            }
        }
        try save(.adultHistory, .scheduledYouth)
        return summary
    }
}
