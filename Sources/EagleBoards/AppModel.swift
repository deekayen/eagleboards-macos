import AppKit
import CheckInServer
import EagleBoardsCore
import Observation
import SwiftUI

/// Everything the windows share: which night is open, the check-in server,
/// and the operator's work in progress on the scheduler.
@MainActor
@Observable
final class AppModel {
    private typealias Keys = LaunchSettings.Keys

    // MARK: - The open night

    private(set) var dataFolder: DataFolder?
    private(set) var night: EventNight?
    var openError: String?

    /// `YYYY-MM-DD` for today, the night opened by default.
    var today: String { Timestamp.dayStamp(for: Date()) }

    init() {
        // For development, EAGLEBOARDS_DATA_FOLDER points the app at a scratch
        // folder of synthetic data without touching the saved choice, and
        // keeps SignUpGenius out of it. See LaunchSettings.
        let launch = LaunchSettings(environment: ProcessInfo.processInfo.environment, defaults: .standard)
        let folderPath = launch.dataFolderPath
        port = launch.port
        importOnOpen = launch.importOnOpen
        proposeBoards = launch.proposeBoards
        signUpGeniusAllowed = launch.signUpGeniusAllowed
        hasSignUpGeniusKey = launch.signUpGeniusAllowed && SignUpGeniusKeychain.exists()
        if let folderPath {
            open(folder: DataFolder(root: URL(filePath: folderPath, directoryHint: .isDirectory)), night: today)
        }
    }

    /// Use `url` as the data folder from now on and open tonight in it.
    func chooseDataFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Keys.dataFolderPath)
        open(folder: DataFolder(root: url), night: today)
    }

    func open(folder: DataFolder, night name: String) {
        do {
            let opened = try EventNight(folder: folder, night: name)
            stopServer()
            dataFolder = folder
            night = opened
            openError = nil
            // Undo steps belong to the night they were taken on.
            undoManager?.removeAllActions()
            attention.forgetNight()
            clearSchedulerSelection()
            startServer()
            if signUpGeniusAllowed, importOnOpen, name == today, hasSignUpGeniusKey {
                Task { await importSignUps() }
            }
        } catch {
            openError = "Could not open \(folder.root.appending(path: name).path): \(error.localizedDescription)"
        }
    }

    // MARK: - The check-in server

    enum ServerState: Equatable {
        case stopped
        case starting
        case running(port: Int)
        case failed(String)
    }

    private(set) var serverState: ServerState = .stopped
    @ObservationIgnored private var serverTask: Task<Void, Never>?
    @ObservationIgnored private var stoppingServerTask: Task<Void, Never>?
    @ObservationIgnored private var keepAwake: NSObjectProtocol?

    var port: Int {
        didSet {
            UserDefaults.standard.set(port, forKey: Keys.port)
            if oldValue != port, night != nil { startServer() }
        }
    }

    var importOnOpen: Bool {
        didSet { UserDefaults.standard.set(importOnOpen, forKey: Keys.importOnOpen) }
    }

    /// Selecting a waiting youth proposes a whole board; off, the board
    /// starts empty for the operator to pick. Settings › General.
    var proposeBoards: Bool {
        didSet {
            UserDefaults.standard.set(proposeBoards, forKey: Keys.proposeBoards)
            refreshProposals()
        }
    }

    /// Addresses the sign-in station can use, venue network first.
    var checkInURLs: [URL] {
        guard case .running(let runningPort) = serverState else { return [] }
        return NetworkAddresses.current().compactMap { URL(string: "http://\($0.ipv4):\(runningPort)/") }
    }

    var isServing: Bool {
        if case .running = serverState { return true }
        return false
    }

    func startServer() {
        stopServer()
        guard let night else { return }
        serverState = .starting
        let requestedPort = port
        // A server just told to stop may still hold the port for a moment.
        // Wait for it to let go, or the new one fails with "address in use".
        let stopping = stoppingServerTask
        serverTask = Task { [weak self] in
            await stopping?.value
            do {
                try await CheckInServer.run(night: night, host: "0.0.0.0", port: requestedPort) { boundPort in
                    await MainActor.run { self?.serverState = .running(port: boundPort) }
                }
            } catch is CancellationError {
            } catch {
                self?.serverState = .failed(Self.describe(serverError: error, port: requestedPort))
            }
        }
        // A laptop that dozes off mid-event takes the sign-in station with
        // it. Keep the Mac awake while serving; the display may still sleep.
        keepAwake = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Serving the Eagle Boards sign-in station"
        )
    }

    func stopServer() {
        if let serverTask {
            serverTask.cancel()
            stoppingServerTask = serverTask
        }
        serverTask = nil
        serverState = .stopped
        if let keepAwake {
            ProcessInfo.processInfo.endActivity(keepAwake)
            self.keepAwake = nil
        }
    }

    private static func describe(serverError error: Error, port: Int) -> String {
        let text = String(describing: error)
        if text.contains("Address already in use") {
            return "Port \(port) is already in use by another program. Quit it -- the Java Eagle Board Scheduler also uses 8080 -- or choose another port in Settings."
        }
        if text.contains("Permission denied") {
            return "macOS would not let Eagle Boards listen on port \(port). Choose a port above 1024 in Settings."
        }
        return "The sign-in station could not start: \(error.localizedDescription)"
    }

    // MARK: - The operator's work in progress

    /// The main window's pages, chosen in the View menu (SPEC.md P-1, P-6),
    /// in the Windows version's order. Event holds every youth, the rooms and
    /// the inspector together (O-3). The rest are a page for each table the
    /// event keeps: the boards (Results), tonight's adults, every youth, the
    /// SignUpGenius pre-registrations, and the rooms, edited in place; and the
    /// Adult History CSV, every adult who has ever signed in, read-only. There is no separate records
    /// window. The inspector stays beside each page.
    enum Page: Hashable, CaseIterable {
        case event
        case results
        case adults
        case youth
        case preRegistered
        case adultHistory
        case rooms
        case approvedProposals

        var title: String {
            switch self {
            case .event: "Event"
            case .results: "Results"
            case .adults: "Adults"
            case .youth: "Youth"
            case .preRegistered: "Pre-Registered"
            case .adultHistory: "Adult History CSV"
            case .rooms: "Rooms"
            case .approvedProposals: "Approved Proposals"
            }
        }

        /// A table File › Export List saves. Results has Export Board Results
        /// instead.
        var isList: Bool { ![.event, .results, .approvedProposals].contains(self) }
    }

    var page: Page = .event
    var searchText = ""
    var showsInspector = true

    var selectedYouthID: Scout.ID?
    var selectedAdultIDs: Set<Adult.ID> = []
    var selectedRoomID: Room.ID?

    /// A board being drawn up for a waiting youth: proposed when they are
    /// selected, then changed by hand in the inspector.
    struct BoardDraft: Equatable {
        var roomID: Room.ID?
        /// Chair first when the suggestion made it, then in the order added.
        var memberIDs: [Adult.ID]
        /// Why the suggestion could not propose a whole board.
        var problems: [String]
        /// Changed by hand. A hand-made board is the operator's work and is
        /// kept while they look at other youth; a proposal is made afresh.
        var isEdited = false
    }

    private(set) var drafts: [Scout.ID: BoardDraft] = [:]

    enum Sheet: Identifiable {
        case seatBoard(scoutID: String)
        case changeMembers(scoutID: String)
        case completeBoard(scoutID: String)
        case addRoom
        case addAdult
        case swapRooms(roomID: String)
        case renameRoom(roomID: String)
        case openNight

        var id: String {
            switch self {
            case .seatBoard(let scoutID): "seat \(scoutID)"
            case .changeMembers(let scoutID): "change members \(scoutID)"
            case .completeBoard(let scoutID): "complete \(scoutID)"
            case .addRoom: "add room"
            case .addAdult: "add adult"
            case .swapRooms(let roomID): "swap \(roomID)"
            case .renameRoom(let roomID): "rename \(roomID)"
            case .openNight: "open event"
            }
        }
    }

    var sheet: Sheet?

    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let actionTitle: String
        var isDestructive = false
        let action: @MainActor () -> Void
    }

    var confirmation: Confirmation?

    /// Something the operator has to read and acknowledge: a refusal, a
    /// failure, or the report of an import.
    struct Message: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    var message: Message?

    var selectedYouth: Scout? { selectedYouthID.flatMap { night?.scout(id: $0) } }
    var selectedRoom: Room? { selectedRoomID.flatMap { night?.room(id: $0) } }
    var selectedAdults: [Adult] {
        guard let night else { return [] }
        return night.adults.filter { selectedAdultIDs.contains($0.id) }
    }

    /// The board drawn up for the selected youth, if they are waiting.
    var draft: BoardDraft? { selectedYouthID.flatMap { drafts[$0] } }

    /// The draft's members, in its order. Someone put on another board since
    /// is still listed, so the inspector can say why they cannot sit.
    func draftMembers(for scoutID: Scout.ID) -> [Adult] {
        guard let night, let draft = drafts[scoutID] else { return [] }
        return draft.memberIDs.compactMap { night.adult(id: $0) }
    }

    func clearSchedulerSelection() {
        selectedYouthID = nil
        selectedAdultIDs = []
        selectedRoomID = nil
        drafts = [:]
    }

    /// Change the main window's page. Each page searches its own list, so
    /// the search starts empty.
    func show(_ newPage: Page) {
        guard newPage != page else { return }
        page = newPage
        searchText = ""
    }

    /// A board picked on Results, on the Event page beside its room.
    func showOnEventPage(_ id: Scout.ID) {
        show(.event)
        selectYouth(id)
    }

    /// Selecting a waiting youth proposes a board, the way the Java scheduler
    /// did, unless the operator has already drawn one up for them by hand.
    func selectYouth(_ id: Scout.ID?) {
        guard id != selectedYouthID || id.map({ drafts[$0] == nil }) == true else { return }
        selectedYouthID = id
        guard let id, let night, let youth = night.scout(id: id) else { return }

        if youth.status?.isWaitingForBoard == true {
            if drafts[id]?.isEdited != true {
                drafts[id] = proposedBoard(for: youth, in: night)
            }
        } else {
            drafts[id] = nil
            selectedRoomID = night.room(named: youth.room)?.id
        }
    }

    /// Throw away any changes and propose a whole board, whether or not
    /// boards are proposed on selection.
    func suggestBoard() {
        guard let night, let youth = selectedYouth, youth.status?.isWaitingForBoard == true else { return }
        drafts[youth.id] = proposedBoard(for: youth, in: night, whole: true)
        // Asked for by hand, so kept even when proposals are off.
        drafts[youth.id]?.isEdited = !proposeBoards
    }

    /// Something a proposal depends on has changed: a room was added or
    /// freed, an adult signed in or left a board. Proposals are made afresh;
    /// boards drawn up by hand are left alone.
    func refreshProposals() {
        drafts = drafts.filter(\.value.isEdited)
        guard let night, let youth = selectedYouth, youth.status?.isWaitingForBoard == true,
              drafts[youth.id] == nil else { return }
        drafts[youth.id] = proposedBoard(for: youth, in: night)
    }

    /// Fill the Rest (SPEC.md D-12): keep who the operator put on the board
    /// and add a chair, if none of them may chair it, and members up to the
    /// working size, chosen as a suggestion would choose them.
    func fillDraft() {
        guard let night, let youth = selectedYouth, youth.status?.isWaitingForBoard == true,
              let draft = drafts[youth.id] else { return }
        let fill = BoardSuggestion.fill(
            for: youth, adults: night.adults, picked: draft.memberIDs,
            waiting: waitingBehind(youth, in: night),
            freeSince: BoardSuggestion.freeSinceTimes(adults: night.adults, scouts: night.scouts))
        drafts[youth.id]?.memberIDs = (fill.chairID.map { [$0] } ?? []) + draft.memberIDs + fill.memberIDs
        drafts[youth.id]?.roomID = draft.roomID ?? night.rooms.first { $0.isFree && $0.boardType == youth.boardType }?.id
        drafts[youth.id]?.problems = fill.problems
        drafts[youth.id]?.isEdited = true
    }

    /// Empty the board, keeping its room.
    func clearDraft() {
        guard let id = selectedYouthID, drafts[id] != nil else { return }
        drafts[id]?.memberIDs = []
        drafts[id]?.problems = []
        drafts[id]?.isEdited = true
    }

    /// The other waiting youth in queue order (pre-registered first), so a
    /// proposal keeps chairs and adults free for the boards to come.
    private func waitingBehind(_ youth: Scout, in night: EventNight) -> [Scout] {
        night.scouts
            .filter { $0.id != youth.id && $0.status?.isWaitingForBoard == true }
            .sorted { $0.queueOrder < $1.queueOrder }
    }

    private func proposedBoard(for youth: Scout, in night: EventNight, whole: Bool? = nil) -> BoardDraft {
        guard whole ?? proposeBoards else {
            // Picking by hand: no one yet, but a free room of the right kind.
            let roomID = night.rooms.first { $0.isFree && $0.boardType == youth.boardType }?.id
            return BoardDraft(roomID: roomID, memberIDs: [], problems: [])
        }
        let freeSince = BoardSuggestion.freeSinceTimes(adults: night.adults, scouts: night.scouts)
        let suggestion = BoardSuggestion(
            for: youth, adults: night.adults, rooms: night.rooms, waiting: waitingBehind(youth, in: night), freeSince: freeSince)
        return BoardDraft(roomID: suggestion.roomID, memberIDs: suggestion.memberIDs, problems: suggestion.problems)
    }

    /// Can the selected adults be added to the board being drawn up?
    var canAddSelectedAdultsToDraft: Bool {
        guard let id = selectedYouthID, let draft = drafts[id] else { return false }
        return selectedAdultIDs.contains { !draft.memberIDs.contains($0) }
    }

    var canRemoveSelectedAdultsFromDraft: Bool {
        guard let draft else { return false }
        return selectedAdultIDs.contains { draft.memberIDs.contains($0) }
    }

    func addToDraft(_ adultIDs: [Adult.ID]) {
        guard let night, let youth = selectedYouth, drafts[youth.id] != nil else {
            message = Message(title: "No board is being drawn up",
                              text: "Select a youth who is waiting, then add adults to their board.")
            return
        }
        let newIDs = adultIDs.filter { night.adult(id: $0) != nil && drafts[youth.id]?.memberIDs.contains($0) == false }
        guard !newIDs.isEmpty else { return }
        drafts[youth.id]?.memberIDs += newIDs
        // The proposal's complaints no longer describe it; the inspector
        // checks the board as it now stands.
        drafts[youth.id]?.problems = []
        drafts[youth.id]?.isEdited = true
    }

    func removeFromDraft(_ adultIDs: Set<Adult.ID>) {
        guard let id = selectedYouthID, drafts[id] != nil else { return }
        drafts[id]?.memberIDs.removeAll { adultIDs.contains($0) }
        // The proposal's complaints no longer describe it; the inspector
        // checks the board as it now stands.
        drafts[id]?.problems = []
        drafts[id]?.isEdited = true
    }

    func setDraftRoom(_ roomID: Room.ID?) {
        guard let id = selectedYouthID, drafts[id] != nil, drafts[id]?.roomID != roomID else { return }
        drafts[id]?.roomID = roomID
        // The proposal's complaints no longer describe it; the inspector
        // checks the board as it now stands.
        drafts[id]?.problems = []
        drafts[id]?.isEdited = true
    }

    /// Clicking a room selects it, and the youth in it if any.
    /// A free room has no youth, so the youth selected before is let go:
    /// the inspector and Next Step must not go on acting on someone the
    /// operator has clicked away from.
    /// Return in the search on the Event page (SPEC.md D-21): open the first
    /// room found, or the youth found if they are in no room.
    func openFirstFound() {
        guard let night, page == .event else { return }
        let find = night.find(searchText)
        if let room = find.rooms.first, !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            selectRoom(room.id)
        } else if let youth = find.people.first(where: \.isYouth) {
            selectYouth(youth.id)
        }
    }

    func selectRoom(_ id: Room.ID) {
        selectedRoomID = id
        let occupant = night?.room(id: id).flatMap { room in
            room.isFree ? nil : night?.scouts.first { $0.room == room.name && !($0.status?.isFinished ?? false) }
        }
        selectYouth(occupant?.id)
    }

    // MARK: - Board actions

    /// Run an event-night change, turning a refusal into a message rather
    /// than a silent failure.
    @discardableResult
    func attempt(_ failure: String, _ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            message = Message(title: failure, text: error.localizedDescription)
            return false
        }
    }

    /// The step that moves the selected youth's board along, if one can be
    /// taken now.
    var nextStep: BoardStep? {
        guard sheet == nil else { return nil }
        return selectedYouth?.status?.nextStep
    }

    func performNextStep() {
        switch nextStep {
        case .seat: beginSeating()
        case .startReview: confirmStartReview()
        case .complete: beginCompleting()
        case nil: break
        }
    }

    func beginSeating() {
        guard let youth = selectedYouth, youth.status?.isWaitingForBoard == true else { return }
        if drafts[youth.id] == nil { selectYouth(youth.id) }
        sheet = .seatBoard(scoutID: youth.id)
    }

    /// A youth dropped on a room: seat their board there.
    func seat(scoutID: Scout.ID, inRoom roomID: Room.ID) {
        guard let night, let youth = night.scout(id: scoutID), let room = night.room(id: roomID) else { return }
        guard youth.status?.isWaitingForBoard == true else {
            message = Message(title: "\(youth.fullName) is not waiting",
                              text: "Only a youth who is waiting for a board can be seated in a room.")
            return
        }
        guard room.isFree else {
            message = Message(title: "Room \(room.name) is in use",
                              text: "\(room.scoutName)'s board is in room \(room.name). Choose a free room.")
            return
        }
        selectYouth(scoutID)
        drafts[scoutID]?.roomID = roomID
        drafts[scoutID]?.isEdited = true
        beginSeating()
    }

    func seat(scoutID: String, roomID: String, chairID: String, memberIDs: [String]) -> Bool {
        let seated = changeBoard(scoutID, "Seat Board", failure: "Could not seat the board") { night in
            try night.seatBoard(roomID: roomID, scoutID: scoutID, chairID: chairID, memberIDs: memberIDs)
        }
        if seated {
            drafts[scoutID] = nil
            selectedRoomID = roomID
            attention.askPermissionIfNeeded()
        }
        return seated
    }

    var canChangeMembers: Bool {
        let status = selectedYouth?.status
        return status == .seated || status == .inProgress
    }

    func beginChangingMembers() {
        guard let youth = selectedYouth, canChangeMembers else { return }
        sheet = .changeMembers(scoutID: youth.id)
    }

    func changeMembers(scoutID: String, chairID: String, memberIDs: [String]) -> Bool {
        changeBoard(scoutID, "Change Members", failure: "Could not change the board members") { night in
            try night.changeMembers(scoutID: scoutID, chairID: chairID, memberIDs: memberIDs)
        }
    }

    func confirmStartReview() {
        guard let night, let youth = selectedYouth else { return }
        let people = AdultLocator.locate(for: youth, among: night.adults)
            .map { "\($0.relation.rawValue): \($0.adult.fullName) (\($0.whereabouts))" }
        let fetch = people.isEmpty ? "" : "\n\nFetch them with the youth:\n" + people.joined(separator: "\n")
        confirmation = Confirmation(
            title: "Start the review?",
            message: "Bring \(youth.fullName) into room \(youth.room) and start the review. Do this once the board has "
                + "finished reading the application, references and project workbook.\(fetch)",
            actionTitle: "Start Review"
        ) { [weak self] in
            self?.changeBoard(youth.id, "Start Review", failure: "Could not start the review") { night in
                try night.startReview(scoutID: youth.id)
            }
        }
    }

    func beginCompleting() {
        guard let youth = selectedYouth, youth.status == .inProgress else { return }
        sheet = .completeBoard(scoutID: youth.id)
    }

    func complete(scoutID: String, result: BoardResult, notes: String) -> Bool {
        changeBoard(scoutID, "Complete", failure: "Could not complete the board") { night in
            try night.completeBoard(scoutID: scoutID, result: result, notes: notes)
        }
    }

    var canPostpone: Bool { selectedYouth?.status?.isWaitingForBoard == true }

    /// Put the selected youth's board off to another night. Undo brings them
    /// back to the waiting list.
    func postpone() {
        guard let youth = selectedYouth, canPostpone else { return }
        if changeBoard(youth.id, "Postpone", failure: "Could not postpone the board", { night in
            try night.postponeBoard(scoutID: youth.id)
        }) {
            drafts[youth.id] = nil
        }
    }

    var canReset: Bool {
        let status = selectedYouth?.status
        return status == .seated || status == .inProgress || status == .verified
    }

    /// Undo seating: the youth waits again and the room and members are
    /// freed. Undo puts the board back, if nobody has taken the room or a
    /// member since.
    func reset() {
        guard let youth = selectedYouth, canReset else { return }
        if changeBoard(youth.id, "Reset Board", failure: "Could not reset the board", { night in
            try night.resetBoard(scoutID: youth.id)
        }) {
            selectYouth(youth.id)
        }
    }

    /// The inspector lists who came with the youth and where they are.
    func locateSelectedYouth() {
        guard selectedYouth != nil else { return }
        showsInspector = true
    }

    // MARK: - Attention

    @ObservationIgnored let attention = Attention()

    var waitingCount: Int {
        night?.scouts.filter { $0.status?.isWaitingForBoard == true }.count ?? 0
    }

    func checkRoomTimers() {
        guard let night else { return }
        attention.checkRooms(in: night, now: Date())
    }

    // MARK: - Undo

    /// The scheduler window's undo manager, which Edit › Undo uses while the
    /// window is in front. Set by the window.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Take one step of a youth's board, and let Undo put it back with
    /// `EventNight.restoreBoard`.
    @discardableResult
    private func changeBoard(_ scoutID: Scout.ID, _ name: String, failure: String, _ step: (EventNight) throws -> Void) -> Bool {
        guard let night, let before = night.scout(id: scoutID) else { return false }
        guard attempt(failure, { try step(night) }), let after = night.scout(id: scoutID) else { return false }
        registerUndo(name, on: night,
                     undo: { try $0.restoreBoard(before) },
                     redo: { try $0.restoreBoard(after) },
                     reveal: { $0.selectYouth(scoutID) })
        return true
    }

    /// Make a change that has a plain inverse, and let Undo apply it.
    @discardableResult
    private func change(_ name: String, failure: String,
                        _ forward: @escaping (EventNight) throws -> Void,
                        undo backward: @escaping (EventNight) throws -> Void) -> Bool {
        guard let night, attempt(failure, { try forward(night) }) else { return false }
        registerUndo(name, on: night, undo: backward, redo: forward)
        return true
    }

    /// Register `undo`, which when run registers `redo` in turn. A refusal
    /// -- the room has been given to another board since, say -- is shown,
    /// and the step stays as it is.
    private func registerUndo(_ name: String, on night: EventNight,
                              undo: @escaping (EventNight) throws -> Void,
                              redo: @escaping (EventNight) throws -> Void,
                              reveal: @escaping (AppModel) -> Void = { _ in }) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            let undoing = model.undoManager?.isUndoing ?? true
            guard model.night === night,
                  model.attempt("Could not \(undoing ? "undo" : "redo") \(name)", { try undo(night) }) else { return }
            model.registerUndo(name, on: night, undo: redo, redo: undo, reveal: reveal)
            model.tidySelection()
            reveal(model)
        }
        undoManager.setActionName(name)
    }

    /// After an undo, let go of anything that is no longer there.
    private func tidySelection() {
        guard let night else { return }
        if let id = selectedRoomID, night.room(id: id) == nil { selectedRoomID = nil }
        selectedAdultIDs = selectedAdultIDs.filter { night.adult(id: $0) != nil }
        for scoutID in drafts.keys {
            if let roomID = drafts[scoutID]?.roomID, night.room(id: roomID) == nil { drafts[scoutID]?.roomID = nil }
        }
    }

    // MARK: - Adults

    /// Disable stands the selected adults down for the night; Enable brings
    /// them back. Undo reverses either.
    func setAvailable(_ available: Bool) {
        let ids = selectedAdults.filter { available ? $0.isDisabledForTonight : $0.isAvailable }.map(\.id)
        guard let night, !ids.isEmpty else { return }
        let names = ids.compactMap { night.adult(id: $0)?.fullName }.joined(separator: ", ")
        let apply: (Bool) -> (EventNight) throws -> Void = { value in
            { night in for id in ids { try night.setAvailable(value, adultID: id) } }
        }
        if change(available ? "Enable" : "Disable", failure: "Could not \(available ? "enable" : "disable") \(names)",
                  apply(available), undo: apply(!available)), !available {
            for scoutID in drafts.keys { drafts[scoutID]?.memberIDs.removeAll { ids.contains($0) } }
        }
    }

    var canEnableSelectedAdults: Bool { selectedAdults.contains(where: \.isDisabledForTonight) }
    var canDisableSelectedAdults: Bool { selectedAdults.contains(where: \.isAvailable) }

    /// The one selected adult, for commands that take a single person.
    var singleSelectedAdult: Adult? {
        let adults = selectedAdults
        return adults.count == 1 ? adults.first : nil
    }

    /// Link the selected adult to the selected youth as someone who came to
    /// support them, or unlink them -- for the adult who did not check the
    /// youth at sign-in. Start Review names them from then on. Works for an
    /// adult on a board too: a Scoutmaster often is by then.
    func toggleSupportLink() {
        guard let adult = singleSelectedAdult, let youth = selectedYouth else { return }
        setSupporting(!adult.supports(youth.id), adultID: adult.id, scoutID: youth.id)
    }

    func setSupporting(_ linked: Bool, adultID: Adult.ID, scoutID: Scout.ID) {
        change(linked ? "Link" : "Unlink", failure: linked ? "Could not link" : "Could not unlink",
               { try $0.setSupporting(linked, adultID: adultID, scoutID: scoutID) },
               undo: { try $0.setSupporting(!linked, adultID: adultID, scoutID: scoutID) })
    }

    // MARK: - Rooms

    func addRoom(named name: String, boardType: BoardType) throws {
        guard let night else { return }
        try night.addRoom(named: name, boardType: boardType)
        let id = Room.roomID(for: name.trimmingCharacters(in: .whitespacesAndNewlines))
        registerUndo("Add Room", on: night,
                     undo: { try $0.removeRoom(id: id) },
                     redo: { try $0.addRoom(named: name, boardType: boardType) })
    }

    /// Remove the selected room. It must be free. Undo adds it back.
    func removeSelectedRoom() {
        guard let room = selectedRoom else { return }
        guard room.isFree else {
            message = Message(title: "Room \(room.name) is in use",
                              text: "\(room.scoutName)'s board is in room \(room.name). A room in use cannot be removed.")
            return
        }
        let boardType = room.boardType ?? .finalBoard
        if change("Remove Room", failure: "Could not remove the room",
                  { try $0.removeRoom(id: room.id) },
                  undo: { try $0.addRoom(named: room.name, boardType: boardType) }) {
            tidySelection()
        }
    }

    /// Rename a room, for the Rename sheet. Returns its new ID.
    func renameRoom(_ id: Room.ID, to newName: String) throws -> Room.ID {
        guard let night, let oldName = night.room(id: id)?.name else { return id }
        let newID = try night.renameRoom(id: id, to: newName)
        roomRenamed(from: id, to: newID)
        guard newID != id else { return newID }
        registerUndo("Rename Room", on: night,
                     undo: { try $0.renameRoom(id: newID, to: oldName) },
                     redo: { try $0.renameRoom(id: id, to: newName) })
        return newID
    }

    /// Move a board to another room, or swap two boards. Swapping again
    /// undoes it.
    func swapRooms(_ firstID: Room.ID, _ secondID: Room.ID) -> Bool {
        let swap: (EventNight) throws -> Void = { try $0.swapRooms(firstID, secondID) }
        guard change("Move Board", failure: "Could not move the board", swap, undo: swap) else { return false }
        selectedRoomID = secondID
        return true
    }

    func setBoardType(_ boardType: BoardType, forRoom roomID: Room.ID) {
        guard let old = night?.room(id: roomID)?.boardType, old != boardType else { return }
        change("Change Room", failure: "Could not change the room",
               { try $0.setBoardType(boardType, forRoom: roomID) },
               undo: { try $0.setBoardType(old, forRoom: roomID) })
    }

    /// After a rename the room keeps its record but not necessarily its ID.
    func roomRenamed(from oldID: Room.ID, to newID: Room.ID) {
        if selectedRoomID == oldID { selectedRoomID = newID }
        for scoutID in drafts.keys where drafts[scoutID]?.roomID == oldID {
            drafts[scoutID]?.roomID = newID
        }
    }

    // MARK: - SignUpGenius

    var isImporting = false
    /// Checked once at launch and after each save, rather than on every
    /// redraw: reading the keychain can put up a prompt.
    private(set) var hasSignUpGeniusKey = false
    /// False when launched on a scratch folder: the keychain's key is for
    /// real sign-ups, which must not land in synthetic data.
    let signUpGeniusAllowed: Bool

    /// Store the key (or remove it, if empty). Returns whether it was saved.
    func saveSignUpGeniusKey(_ key: String) -> Bool {
        guard signUpGeniusAllowed else { return false }
        let saved = SignUpGeniusKeychain.write(key)
        hasSignUpGeniusKey = SignUpGeniusKeychain.exists()
        return saved
    }

    func importSignUps() async {
        guard let night else { return }
        guard signUpGeniusAllowed else {
            message = Message(title: "SignUpGenius is off",
                              text: "SignUpGenius is off while EAGLEBOARDS_DATA_FOLDER is set. Set EAGLEBOARDS_SIGNUPGENIUS=1 to use it.")
            return
        }
        guard let key = SignUpGeniusKeychain.read() else {
            message = Message(title: "No SignUpGenius key", text: "Add your SignUpGenius API key in Settings first.")
            return
        }
        isImporting = true
        defer { isImporting = false }
        let client = SignUpGeniusClient(apiKey: key)
        do {
            let signup = try await client.findActiveSignup(today: night.night)
            let entries = try await client.filledSlots(signupID: signup.id)
            let summary = try night.mergeSignUps(entries, month: String(night.night.prefix(7)))
            var lines = [
                "\(summary.addedYouth) youth pre-registered, \(summary.alreadyScheduledYouth) already were.",
                "\(summary.addedAdults) adults added to the history, \(summary.updatedAdults) updated.",
            ]
            if summary.skippedDuplicateAdults > 0 {
                lines.append("\(summary.skippedDuplicateAdults) skipped: their email is on more than one history record.")
            }
            message = Message(title: "Imported \(signup.title)", text: lines.joined(separator: "\n"))
        } catch {
            message = Message(title: "Could not import sign-ups", text: error.localizedDescription)
        }
    }

    // MARK: - Records, edited in place

    /// Sign an adult in by hand, as the tablet would, and select them on the
    /// Adults page. Like a sign-in at the door, it is not undone; Delete
    /// Adult takes a mistake off tonight's list.
    func addAdult(_ form: [String: String]) throws {
        guard let night else { return }
        let adult = try night.registerAdult(form)
        selectedAdultIDs = [adult.id]
    }

    /// Sign adults in for today straight from the Adult History CSV page, with
    /// the details and roles on file, as if each had signed in at the tablet.
    func signInFromHistory(_ ids: Set<Adult.ID>) {
        guard let night else { return }
        for known in night.adultHistory where ids.contains(known.id) {
            attempt("Could not sign in \(known.fullName)") {
                _ = try night.registerAdult(Adult.handSignInForm(
                    historyID: known.id, first: known.first, last: known.last, email: known.email, phone: known.phone,
                    unitType: known.unitType, unit: known.unit, finalBoard: nil, projectReview: nil, woodBadge: false
                ))
            }
        }
    }

    /// Save a cell changed on the Results, Youth or Pre-Registered page. A
    /// changed cell is saved as it is left and stays off the Undo stack
    /// (SPEC.md P-6), which is kept for the Event page's steps.
    @discardableResult
    func editYouth(_ id: Scout.ID, scheduled: Bool = false, _ edit: (inout Scout) -> Void) -> Bool {
        guard let night, var record = (scheduled ? night.scheduledScouts : night.scouts).first(where: { $0.id == id }) else {
            return false
        }
        let name = record.fullName
        edit(&record)
        return attempt("Could not change \(name)") { try night.updateYouth(record, scheduled: scheduled) }
    }

    /// Save a cell changed on the Adults page: promoting someone to Chair,
    /// say. Off the Undo stack, as `editYouth`; the adult history follows.
    @discardableResult
    func editAdult(_ id: Adult.ID, _ edit: (inout Adult) -> Void) -> Bool {
        guard let night, var record = night.adult(id: id) else { return false }
        let name = record.fullName
        edit(&record)
        return attempt("Could not change \(name)") { try night.updateAdult(record) }
    }

    /// The Rooms page's Board Type cell: off the Undo stack like any cell
    /// (P-6). Room › Used For, an Event page step, is undoable.
    @discardableResult
    func editRoomType(_ id: Room.ID, to boardType: BoardType) -> Bool {
        guard let night else { return false }
        return attempt("Could not change the room") { try night.setBoardType(boardType, forRoom: id) }
    }

    /// A deleted record leaves the file and Undo cannot bring it back, so
    /// this one asks first.
    func confirmDeleteYouth(_ id: Scout.ID, scheduled: Bool = false) {
        guard let night, let youth = (scheduled ? night.scheduledScouts : night.scouts).first(where: { $0.id == id }) else {
            return
        }
        confirmation = Confirmation(
            title: "Delete \(youth.fullName)?",
            message: "The record is removed from the file. This cannot be undone.",
            actionTitle: "Delete",
            isDestructive: true
        ) { [weak self] in
            guard let self, attempt("Could not delete \(youth.fullName)", { try night.deleteYouth(id: id, scheduled: scheduled) })
            else { return }
            if !scheduled && selectedYouthID == id { selectYouth(nil) }
        }
    }

    func confirmDeleteAdult(_ id: Adult.ID) {
        guard let night, let adult = night.adult(id: id) else { return }
        confirmation = Confirmation(
            title: "Delete \(adult.fullName)?",
            message: "They are taken off today's list; the adult history keeps them. This cannot be undone.",
            actionTitle: "Delete",
            isDestructive: true
        ) { [weak self] in
            guard let self, attempt("Could not delete \(adult.fullName)", { try night.deleteAdult(id: id) }) else { return }
            selectedAdultIDs.remove(id)
            for scoutID in drafts.keys { drafts[scoutID]?.memberIDs.removeAll { $0 == id } }
        }
    }

    // MARK: - Files

    /// Save the page's list as a spreadsheet, with the data files' columns
    /// but never a youth's birthdate or phone number (SPEC.md D-7, D-8).
    func exportList() {
        guard let night, page.isList else { return }
        let text = switch page {
        case .event, .results, .approvedProposals: ""
        case .rooms: CSVFile.render(night.rooms)
        case .youth: CSVFile.render(night.scouts.map(\.forExport))
        case .preRegistered: CSVFile.render(night.scheduledScouts.map(\.forExport))
        case .adults: CSVFile.render(night.adults)
        case .adultHistory: CSVFile.render(night.adultHistory)
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(page.title) \(night.night).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "This list holds personal information. Keep the file somewhere private."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            message = Message(title: "Could not save the list", text: error.localizedDescription)
        }
    }

    func exportReport() {
        guard let night else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Board Results \(night.night).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "The report holds names and contact details, including those of minors. Keep it somewhere private."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(Reports.csv(night.scouts, columns: Reports.boardResultColumns).utf8).write(to: url, options: .atomic)
        } catch {
            message = Message(title: "Could not save the report", text: error.localizedDescription)
        }
    }

    func showDataFolderInFinder() {
        guard let night else { return }
        NSWorkspace.shared.activateFileViewerSelecting([night.folder.nightFolder(night.night)])
    }

    func chooseDataFolderWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder for Eagle Boards data. If you used the Java Eagle Board Scheduler, "
            + "choose the folder it ran in -- the one with Master_AdultHistory.csv and the dated folders."
        if panel.runModal() == .OK, let url = panel.url {
            chooseDataFolder(url)
        }
    }

    /// `~/Documents/Eagle Boards`, created if it is not there.
    func useDefaultDataFolder() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appending(path: "Eagle Boards", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            chooseDataFolder(folder)
        } catch {
            openError = "Could not create \(folder.path): \(error.localizedDescription)"
        }
    }
}
