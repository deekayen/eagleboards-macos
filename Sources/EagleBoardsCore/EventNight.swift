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

/// One event night: everyone who has signed in, the rooms, and every board.
///
/// All state lives on the main actor. The scheduler window reads it directly,
/// and the check-in server hops onto the main actor to register someone, so a
/// sign-in shows up on the operator's screen the moment it happens. Every
/// change is written to disk before the call returns, as the Java app did, so
/// quitting at any moment loses nothing.
@MainActor
@Observable
public final class EventNight {
    public let folder: DataFolder
    /// `YYYY-MM-DD`, the name of this night's folder.
    public let night: String

    /// Youth who have signed in tonight (`scouts.csv`).
    public private(set) var scouts: [Scout] = []
    /// Youth pre-registered for tonight, from SignUpGenius (`scouts_scheduled.csv`).
    public private(set) var scheduledScouts: [Scout] = []
    /// Adults who have signed in tonight (`adults.csv`).
    public private(set) var adults: [Adult] = []
    /// Every adult who has ever signed in (`Master_AdultHistory.csv`).
    public private(set) var adultHistory: [Adult] = []
    public private(set) var rooms: [Room] = []
    public private(set) var config: Config = .standard

    @ObservationIgnored private let clock: @Sendable () -> Date

    /// Opens (creating if needed) the night's folder inside `folder`.
    public init(folder: DataFolder, night: String, clock: @escaping @Sendable () -> Date = { Date() }) throws {
        self.folder = folder
        self.night = night
        self.clock = clock

        try FileManager.default.createDirectory(at: folder.nightFolder(night), withIntermediateDirectories: true)
        scouts = try CSVFile.read(Scout.self, from: folder.youthURL(night: night))
        scheduledScouts = try CSVFile.read(Scout.self, from: folder.scheduledYouthURL(night: night))
        adults = try CSVFile.read(Adult.self, from: folder.adultsURL(night: night))
        adultHistory = try CSVFile.read(Adult.self, from: folder.adultHistoryURL)
        rooms = try CSVFile.read(Room.self, from: folder.roomsURL(night: night))
        config = try PropertiesFile.read(from: folder.configURL)

        // Leave a complete, readable folder behind even if nothing happens
        // tonight -- the Java app created every file at startup too.
        for table in Table.allCases where !FileManager.default.fileExists(atPath: url(of: table).path) {
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
        case .youth: folder.youthURL(night: night)
        case .scheduledYouth: folder.scheduledYouthURL(night: night)
        case .adults: folder.adultsURL(night: night)
        case .adultHistory: folder.adultHistoryURL
        case .rooms: folder.roomsURL(night: night)
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

    // MARK: - Signing in

    /// A youth signs in at the check-in station.
    ///
    /// Signing in again updates the sign-in fields and nothing else, so it
    /// cannot move a youth's board along or change their result. A youth who
    /// matches a pre-registration (by ID or email) gets a `P` number, anyone
    /// else a `W` for walk-in; the number counts sign-ins within that group.
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

        let preRegistered = scheduledScouts.contains { $0.id == incoming.id }
            || scheduledYouth(matchingEmail: incoming.email) != nil
        let nextRegNum = preRegistered
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
    /// Tonight's record is created or updated, and so is the adult's permanent
    /// history record, which gains tonight's date. Signing in again does not
    /// take them off a board they are already sitting on.
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

        var tonight: Adult
        let tonightIndex: Int
        if let index = adults.firstIndex(where: { $0.id == incoming.id }) {
            adults[index].update(from: incoming, columns: Adult.signInColumns)
            tonightIndex = index
        } else {
            adults.append(incoming)
            tonightIndex = adults.count - 1
        }
        tonight = adults[tonightIndex]

        // Still no role: whatever the history says, or Member.
        let historyMatch = adultHistory.firstIndex(where: { $0.id == tonight.id })
        for column in roleColumns where tonight[column].isEmpty {
            let known = historyMatch.map { adultHistory[$0][column] } ?? ""
            tonight[column] = BoardRole(rawValue: known) != nil ? known : BoardRole.member.rawValue
        }

        let dayMark = "(\(Timestamp.dayStamp(for: now)))"
        if let historyIndex = historyMatch {
            adultHistory[historyIndex].update(from: tonight, columns: Adult.signInColumns)
            tonight.flags = "P"
            if !adultHistory[historyIndex].boardHistory.hasSuffix(dayMark) {
                adultHistory[historyIndex].boardHistory += dayMark
            }
        } else {
            var history = tonight
            history.regTime = Timestamp.recordStamp(for: now)
            history.room = ""
            history.flags = ""
            history["Sel"] = ""
            history.boardHistory += dayMark
            adultHistory.append(history)
            tonight.flags = "W"
        }
        adults[tonightIndex] = tonight
        try save(.adults, .adultHistory)
        return tonight
    }

    // MARK: - The board lifecycle

    /// Convene a board: the members get the room and the paperwork, and the
    /// youth waits outside until Start Review.
    ///
    /// This is the hard backstop for the composition rules. The Seat Board
    /// sheet explains them first, but a request that skipped the sheet must
    /// still be refused here.
    public func seatBoard(roomID: String, scoutID: String, chairID: String, memberIDs: [String]) throws {
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }) else {
            throw EventError("There is no room '\(roomID)'.")
        }
        let room = rooms[roomIndex]
        guard room.isFree else {
            throw EventError("Room \(room.name) is already in use by \(room.scoutName).")
        }
        guard let scoutIndex = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        var scout = scouts[scoutIndex]
        guard scout.status?.isWaitingForBoard == true else {
            throw EventError("\(scout.fullName) cannot be seated from status '\(scout.statusText)'.")
        }
        // disabledForTonightMarker ("N/A") is what Complete leaves in a youth's
        // room. A Registered youth holding it had a result recorded against them
        // by mistake and was set back in the Records window: they have no room
        // and must be seatable for their real board.
        guard scout.room.isEmpty || scout.room == disabledForTonightMarker || scout.room == room.name else {
            throw EventError("\(scout.fullName) is already assigned to room \(scout.room).")
        }
        guard let boardType = scout.boardType else {
            throw EventError("\(scout.fullName) has no board type.")
        }

        var seenIDs = Set<String>()
        let uniqueMemberIDs = memberIDs
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seenIDs.insert($0).inserted }
        guard !uniqueMemberIDs.isEmpty else {
            throw EventError("No board members are selected.")
        }

        var members: [Adult] = []
        for memberID in uniqueMemberIDs {
            guard let member = adult(id: memberID) else {
                throw EventError("There is no adult '\(memberID)'.")
            }
            if member.isDisabledForTonight {
                throw EventError("\(member.fullName) has been disabled for tonight.")
            }
            if !member.room.isEmpty {
                throw EventError("\(member.fullName) is already on the board in room \(member.room).")
            }
            members.append(member)
        }

        let minimum = BoardRules.minimumMembers(for: boardType)
        switch BoardRules.checkSize(members.count, for: boardType) {
        case .tooFew:
            throw EventError("Only \(members.count) board member(s) selected; \(minimum) required for a \(boardType.label).")
        case .tooMany:
            throw EventError("\(members.count) board members selected; no more than \(BoardRules.boardMaximum) permitted (Guide to Advancement 8.0.0.3).")
        case .ok, .overPreferred:
            break
        }

        // The Chair designation is binding. Promoting someone is a deliberate
        // edit in the Records window, never a side effect of seating a board
        // because the qualified chairs were all busy.
        guard let chair = adult(id: chairID) else {
            throw EventError("There is no adult '\(chairID)' to chair the board.")
        }
        guard uniqueMemberIDs.contains(chair.id) else {
            throw EventError("\(chair.fullName) is chairing but is not one of the board members.")
        }
        guard chair.canChair(boardType) else {
            let role = chair.role(for: boardType)?.rawValue ?? "none"
            throw EventError("\(chair.fullName) is not qualified to chair a \(boardType.label) (role: \(role)).")
        }

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

    /// Bring the youth into the room and begin the review.
    public func startReview(scoutID: String) throws {
        guard let index = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        guard scouts[index].status == .seated else {
            throw EventError("\(scouts[index].fullName)'s board has not been seated (status '\(scouts[index].statusText)').")
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
    public func completeBoard(scoutID: String, result: BoardResult, notes: String) throws {
        guard let scoutIndex = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        guard scouts[scoutIndex].status == .inProgress else {
            throw EventError("\(scouts[scoutIndex].fullName)'s review has not started (status '\(scouts[scoutIndex].statusText)').")
        }
        let roomName = scouts[scoutIndex].room
        guard let roomIndex = rooms.firstIndex(where: { $0.name == roomName }) else {
            throw EventError("Room \(roomName) was not found.")
        }
        releaseRoom(at: roomIndex)
        scouts[scoutIndex].status = .completed
        scouts[scoutIndex].room = disabledForTonightMarker
        scouts[scoutIndex].notes = notes
        scouts[scoutIndex].result = result.rawValue
        scouts[scoutIndex].markUpdated(at: now)
        try save(.youth, .rooms, .adults)
    }

    /// Put a waiting youth's board off to another night.
    public func postponeBoard(scoutID: String) throws {
        guard let index = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        guard scouts[index].status?.isWaitingForBoard == true else {
            throw EventError("Only a youth still waiting can be postponed; \(scouts[index].fullName) is '\(scouts[index].statusText)'.")
        }
        scouts[index].status = .postponed
        scouts[index].markUpdated(at: now)
        try save(.youth)
    }

    /// Undo seating: the youth goes back to waiting, and the room and the
    /// members are free again.
    public func resetBoard(scoutID: String) throws {
        guard let scoutIndex = scouts.firstIndex(where: { $0.id == scoutID }) else {
            throw EventError("There is no youth '\(scoutID)'.")
        }
        let status = scouts[scoutIndex].status
        guard status == .seated || status == .inProgress || status == .verified else {
            throw EventError("Only a seated board or a review in progress can be reset; \(scouts[scoutIndex].fullName) is '\(scouts[scoutIndex].statusText)'.")
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

    private func releaseRoom(at roomIndex: Int) {
        let roomName = rooms[roomIndex].name
        for index in adults.indices where adults[index].room == roomName {
            adults[index].room = ""
        }
        rooms[roomIndex].scoutName = ""
        rooms[roomIndex].leaderNames = ""
    }

    // MARK: - Rooms

    public func addRoom(named rawName: String, boardType: BoardType) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw EventError("Enter a room name.")
        }
        guard !name.contains(",") else {
            throw EventError("A room name cannot contain a comma.")
        }
        guard room(id: Room.roomID(for: name)) == nil else {
            throw EventError("Room \(name) already exists.")
        }
        var newRoom = Room.blank(at: now)
        newRoom["ID"] = Room.roomID(for: name)
        newRoom.name = name
        newRoom.boardTypeText = boardType.rawValue
        rooms.append(newRoom)
        try save(.rooms)
    }

    public func removeRoom(id: String) throws {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else {
            throw EventError("There is no room '\(id)'.")
        }
        guard rooms[index].isFree else {
            throw EventError("Room \(rooms[index].name) is in use by \(rooms[index].scoutName) and cannot be removed.")
        }
        rooms.remove(at: index)
        try save(.rooms)
    }

    public func setBoardType(_ boardType: BoardType, forRoom id: String) throws {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else {
            throw EventError("There is no room '\(id)'.")
        }
        rooms[index].boardTypeText = boardType.rawValue
        try save(.rooms)
    }

    /// Swap everything between two rooms: the youth, the members and the
    /// names on the cards. Either room may be empty, which makes this a move.
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

    /// Add the rooms from an earlier night that tonight does not have yet,
    /// empty, so the room list does not have to be typed in every month.
    @discardableResult
    public func copyRooms(fromNight earlierNight: String) throws -> Int {
        let earlierRooms = try CSVFile.read(Room.self, from: folder.roomsURL(night: earlierNight))
        var added = 0
        for earlier in earlierRooms where !earlier.name.isEmpty && room(id: Room.roomID(for: earlier.name)) == nil {
            var copy = Room.blank(at: now)
            copy["ID"] = Room.roomID(for: earlier.name)
            copy.name = earlier.name
            copy.boardTypeText = earlier.boardTypeText
            rooms.append(copy)
            added += 1
        }
        if added > 0 {
            try save(.rooms)
        }
        return added
    }

    // MARK: - Adults

    /// Enable or Disable: stand an adult down for the night, or bring them back.
    public func setAvailable(_ available: Bool, adultID: String) throws {
        guard let index = adults.firstIndex(where: { $0.id == adultID }) else {
            throw EventError("There is no adult '\(adultID)'.")
        }
        let adult = adults[index]
        if available {
            guard adult.isDisabledForTonight else {
                throw EventError("\(adult.fullName) is not disabled.")
            }
            adults[index].room = ""
        } else {
            if adult.isDisabledForTonight {
                throw EventError("\(adult.fullName) is already disabled.")
            }
            guard adult.room.isEmpty else {
                throw EventError("\(adult.fullName) is on the board in room \(adult.room). Reset or complete that board first.")
            }
            adults[index].room = disabledForTonightMarker
        }
        try save(.adults)
    }

    // MARK: - Editing records directly

    /// Replace a youth record as edited in the Records window.
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
            scouts[index] = record
            try save(.youth)
        }
    }

    public func deleteYouth(id: String, scheduled: Bool = false) throws {
        if scheduled {
            scheduledScouts.removeAll { $0.id == id }
            try save(.scheduledYouth)
        } else {
            if let scout = scout(id: id), scout.status == .seated || scout.status == .inProgress {
                throw EventError("\(scout.fullName)'s board is active in room \(scout.room). Reset it before deleting.")
            }
            scouts.removeAll { $0.id == id }
            try save(.youth)
        }
    }

    /// Replace an adult record as edited in the Records window.
    public func updateAdult(_ edited: Adult, history: Bool = false) throws {
        var record = edited
        record.refreshDerivedFields()
        if history {
            guard let index = adultHistory.firstIndex(where: { $0.id == edited.id }) else {
                throw EventError("That history record no longer exists.")
            }
            adultHistory[index] = record
            try save(.adultHistory)
        } else {
            guard let index = adults.firstIndex(where: { $0.id == edited.id }) else {
                throw EventError("That adult no longer exists.")
            }
            adults[index] = record
            try save(.adults)
        }
    }

    public func deleteAdult(id: String, history: Bool = false) throws {
        if history {
            adultHistory.removeAll { $0.id == id }
            try save(.adultHistory)
        } else {
            if let adult = adult(id: id), adult.isOnBoard {
                throw EventError("\(adult.fullName) is on the board in room \(adult.room). Reset or complete that board first.")
            }
            adults.removeAll { $0.id == id }
            try save(.adults)
        }
    }

    public func updateConfig(_ edited: Config) throws {
        config = Config(fields: edited.fields)
        try save(.config)
    }

    // MARK: - SignUpGenius

    public struct SignUpImportSummary: Sendable, Equatable {
        public var addedAdults = 0
        public var updatedAdults = 0
        public var skippedDuplicateAdults = 0
        public var addedYouth = 0
        public var alreadyScheduledYouth = 0
        public var outsideThisMonth = 0

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
    }

    /// Merge SignUpGenius sign-ups into the adult history and tonight's
    /// pre-registrations.
    ///
    /// Only entries dated in `month` (`YYYY-MM`) are used -- by calendar month,
    /// as the Java app did, so two board nights in one month both import. An
    /// adult is matched to the history by email: one match gets their phone
    /// updated, none adds them as a Member for both board types, and more than
    /// one is left alone rather than guessed at.
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
                    Self.matchableEmail($0.email) != nil && Self.matchableEmail($0.email) == Self.matchableEmail(entry.email)
                }) {
                    summary.alreadyScheduledYouth += 1
                    continue
                }
                var youth = Scout.blank(at: now)
                youth.first = NameCleanup.name(entry.firstName)
                youth.last = NameCleanup.name(entry.lastName)
                youth.email = entry.email.trimmingCharacters(in: .whitespaces)
                youth.phone = NameCleanup.phone(entry.phoneText)
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
