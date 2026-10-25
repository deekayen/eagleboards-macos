import AppKit
import CheckInServer
import EagleBoardsCore
import Observation
import SwiftUI

/// Everything the windows share: which event is open, the check-in server,
/// and the operator's work in progress on the scheduler.
@MainActor
@Observable
final class AppModel {
    private typealias Keys = LaunchSettings.Keys

    // MARK: - The open event

    private(set) var dataFolder: DataFolder?
    private(set) var event: BoardEvent?
    var openError: String?

    /// `YYYY-MM-DD` for today, the event opened by default.
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
            open(folder: DataFolder(root: URL(filePath: folderPath, directoryHint: .isDirectory)), event: today)
        }
        showWaitingOnTheDock()
    }

    /// Use `url` as the data folder from now on and open today's event in it.
    /// A folder whose event cannot be opened is not kept as the choice.
    func chooseDataFolder(_ url: URL) {
        if open(folder: DataFolder(root: url), event: today) {
            UserDefaults.standard.set(url.path, forKey: Keys.dataFolderPath)
        }
    }

    /// Open an event, or say why not: on the welcome screen when no event is
    /// open, or in an alert over the event that stays open.
    @discardableResult
    func open(folder: DataFolder, event name: String) -> Bool {
        do {
            try openOrThrow(folder: folder, event: name)
            return true
        } catch {
            let path = folder.eventFolder(name).path
            openError = "Could not open \(path): \(error.localizedDescription)"
            if event != nil {
                message = Message(title: "Could Not Open the \(name) Event",
                                  text: "\(error.localizedDescription)\n\nThe event's folder is \(path).")
            }
            return false
        }
    }

    /// Open an event, or throw why not, for the Open Another Event sheet,
    /// which says it inside the sheet: an alert would wait behind it.
    func openOrThrow(folder: DataFolder, event name: String) throws {
        let opened = try BoardEvent(folder: folder, date: name)
        stopServer()
        dataFolder = folder
        event = opened
        openError = nil
        // Undo steps belong to the event they were taken on, and so do a
        // sheet or question still up.
        undoManager?.removeAllActions()
        sheet = nil
        confirmation = nil
        attention.forgetEvent()
        clearSchedulerSelection()
        startServer()
        startCheckingRooms()
        // SPEC.md D-9, said only on the open that made it, so someone who
        // picked the wrong folder learns it before the event starts.
        if opened.createdAdultHistory {
            message = Message(
                title: "Started a New Adult History",
                text: "This data folder had no adult history, so Eagle Boards started a new, empty one:\n\n"
                    + "\(folder.adultHistoryURL.path)\n\n"
                    + "If you meant a folder that already has one, choose it with File › Choose Data Folder… instead.")
        }
        if signUpGeniusAllowed, importOnOpen, name == today, hasSignUpGeniusKey {
            Task { await importSignUps() }
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
            if oldValue != port, event != nil { startServer() }
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
    var checkInAddresses: [CheckInAddress] {
        guard case .running(let runningPort) = serverState else { return [] }
        let names = NetworkAddresses.displayNames()
        // One item per address: the Network picker tags each by its host.
        var seen: Set<String> = []
        return NetworkAddresses.current().compactMap { address in
            URL(string: "http://\(address.ipv4):\(runningPort)/").map {
                CheckInAddress(network: names[address.interface] ?? address.interface, url: $0)
            }
        }
        .filter { seen.insert($0.host).inserted }
    }

    /// The event the sign-in station is serving, said beside it when that
    /// is not today's.
    var servedEventNote: String? {
        event.flatMap { DataFolder.servedEventNote($0.date, today: today) }
    }

    var isServing: Bool {
        if case .running = serverState { return true }
        return false
    }

    var serverFailed: Bool {
        if case .failed = serverState { return true }
        return false
    }

    /// The sign-in page on this Mac, while the station is serving.
    var localSignInURL: URL? {
        guard case .running(let runningPort) = serverState else { return nil }
        return URL(string: "http://127.0.0.1:\(runningPort)/")
    }

    func startServer() {
        stopServer()
        guard let event else { return }
        serverState = .starting
        let requestedPort = port
        // A server just told to stop may still hold the port for a moment.
        // Wait for it to let go, or the new one fails with "address in use".
        let stopping = stoppingServerTask
        serverTask = Task { [weak self] in
            await stopping?.value
            do {
                try await CheckInServer.run(event: event, host: "0.0.0.0", port: requestedPort) { boundPort in
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
            return LaunchSettings.portInUse(port)
        }
        if text.contains("Permission denied") {
            return LaunchSettings.portRefused(port)
        }
        return "The sign-in station could not start: \(error.localizedDescription)"
    }

    // MARK: - The operator's work in progress

    /// The main window's pages, chosen in the View menu (SPEC.md P-1, P-6),
    /// in the Windows version's order. Event holds every youth, the rooms and
    /// the inspector together (O-3). The rest are a page for each table the
    /// event keeps: the boards (Results), the event's adults, every youth, the
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

        /// What File › Export List names the saved file, before the event's
        /// date. The saved file is the CSV, so the page's "CSV" is left out.
        var exportName: String { self == .adultHistory ? "Adult History" : title }
    }

    var page: Page = .event
    var searchText = ""
    var showsInspector = true
    /// Edit › Find… asked for the toolbar search. The scheduler window takes
    /// it up when it next draws, which may be once Find has opened it.
    var findRequested = false
    /// Board › Locate Leader and Parents asked for the inspector's With Them
    /// section, which the inspector scrolls to once it is on screen.
    var locateRequested = false

    var selectedYouthID: Scout.ID?
    /// Picked on the Adults page, and let go when it is left.
    var selectedAdultIDs: Set<Adult.ID> = []
    var selectedRoomID: Room.ID?
    /// Picked on the Adult History CSV page, for Adult › Sign In for Today.
    var selectedHistoryIDs: Set<Adult.ID> = []

    /// The boards being drawn up for waiting youth (SPEC.md D-12).
    private(set) var drafts = BoardDrafts()

    enum Sheet: Identifiable {
        case seatBoard(scoutID: String)
        case changeMembers(scoutID: String)
        case completeBoard(scoutID: String)
        case addRoom
        case addAdult
        case swapRooms(roomID: String)
        case renameRoom(roomID: String)
        case openEvent

        var id: String {
            switch self {
            case .seatBoard(let scoutID): "seat \(scoutID)"
            case .changeMembers(let scoutID): "change members \(scoutID)"
            case .completeBoard(let scoutID): "complete \(scoutID)"
            case .addRoom: "add room"
            case .addAdult: "add adult"
            case .swapRooms(let roomID): "swap \(roomID)"
            case .renameRoom(let roomID): "rename \(roomID)"
            case .openEvent: "open event"
            }
        }
    }

    var sheet: Sheet? {
        didSet {
            // The board in an open Seat Board sheet is the one the operator
            // is checking: it stays as it is until the sheet closes, then
            // catches up on whoever signed in meanwhile.
            if case .seatBoard(let scoutID) = sheet {
                drafts.frozenID = scoutID
            } else if drafts.frozenID != nil {
                drafts.frozenID = nil
                refreshProposals()
            }
        }
    }

    struct Confirmation: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let actionTitle: String
        var isDestructive = false
        let action: @MainActor () -> Void
    }

    var confirmation: Confirmation?

    /// Opens a window by its `WindowID`, or brings it forward. Set by the
    /// scheduler window, or by the Sign-In Code window when it is the first
    /// to appear; the Dock menu opens windows through it too.
    @ObservationIgnored var openWindow: (@MainActor (String) -> Void)?

    /// Sheets and confirmations are shown on the scheduler window, so a
    /// command that puts one up opens it first: the menu bar works with the
    /// window closed, and the sheet would otherwise wait there unseen.
    func openScheduler() {
        openWindow?(WindowID.scheduler)
    }

    func present(_ newSheet: Sheet) {
        openScheduler()
        sheet = newSheet
    }

    func present(_ newConfirmation: Confirmation) {
        openScheduler()
        confirmation = newConfirmation
    }

    /// Something the operator has to read and acknowledge: a refusal, a
    /// failure, or the report of an import.
    struct Message: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    var message: Message?

    var selectedYouth: Scout? { selectedYouthID.flatMap { event?.scout(id: $0) } }
    var selectedRoom: Room? { selectedRoomID.flatMap { event?.room(id: $0) } }
    var selectedAdults: [Adult] {
        guard let event else { return [] }
        return event.adults.filter { selectedAdultIDs.contains($0.id) }
    }

    /// The board drawn up for the selected youth, if they are waiting.
    var draft: BoardDraft? { selectedYouthID.flatMap { drafts[$0] } }

    /// The draft's members, in its order. Someone put on another board since
    /// is still listed, so the inspector can say why they cannot sit.
    func draftMembers(for scoutID: Scout.ID) -> [Adult] {
        guard let event, let draft = drafts[scoutID] else { return [] }
        return draft.memberIDs.compactMap { event.adult(id: $0) }
    }

    func clearSchedulerSelection() {
        selectedYouthID = nil
        selectedAdultIDs = []
        selectedRoomID = nil
        selectedHistoryIDs = []
        drafts.removeAll()
    }

    /// Change the main window's page. Each page searches its own list, so
    /// the search starts empty. The adults picked on the Adults page or the
    /// Adult History CSV page are let go with it, so the Adult menu never
    /// acts on people the page shown does not list.
    func show(_ newPage: Page) {
        guard newPage != page else { return }
        if page == .adults { selectedAdultIDs = [] }
        if page == .adultHistory { selectedHistoryIDs = [] }
        page = newPage
        searchText = ""
    }

    /// Those picked on the Adult History CSV page who have not signed in
    /// today, while it is the page shown.
    var historySelectionToSignIn: Set<Adult.ID> {
        guard let event, page == .adultHistory else { return [] }
        return selectedHistoryIDs.subtracting(event.adults.map(\.id))
    }

    /// A board picked on Results, on the Event page beside its room.
    func showOnEventPage(_ id: Scout.ID) {
        show(.event)
        selectYouth(id)
    }

    /// A room picked on the Rooms page, its card selected on the Event page.
    func showRoomOnEventPage(_ id: Room.ID) {
        show(.event)
        selectRoom(id)
    }

    /// Selecting a waiting youth proposes a board, the way the Java scheduler
    /// did, unless the operator has already drawn one up for them by hand.
    func selectYouth(_ id: Scout.ID?) {
        guard id != selectedYouthID || id.map({ drafts[$0] == nil }) == true else { return }
        selectedYouthID = id
        guard let id, let event, let youth = event.scout(id: id) else { return }

        drafts.select(youth, in: event, proposing: proposeBoards)
        if youth.status?.isWaitingForBoard != true {
            selectedRoomID = event.room(named: youth.room)?.id
        }
    }

    /// Throw away any changes and propose a whole board, whether or not
    /// boards are proposed on selection.
    func suggestBoard() {
        guard let event, let youth = selectedYouth else { return }
        drafts.suggest(for: youth, in: event, proposing: proposeBoards)
    }

    /// Something a proposal is made from has changed (`BoardDrafts.fingerprint`):
    /// a room was added or freed, an adult signed in or left a board.
    /// Proposals are made afresh; boards drawn up by hand are left alone.
    func refreshProposals() {
        guard let event else { return }
        drafts.refresh(selected: selectedYouth, in: event, proposing: proposeBoards)
    }

    func fillDraft() {
        guard let event, let youth = selectedYouth else { return }
        drafts.fill(for: youth, in: event)
    }

    func clearDraft() {
        guard let id = selectedYouthID else { return }
        drafts.clear(id)
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
        guard let event, let youth = selectedYouth, drafts[youth.id] != nil else {
            message = Message(title: "No board is being drawn up.",
                              text: "Select a youth who is waiting, then add adults to their board.")
            return
        }
        drafts.add(adultIDs, for: youth.id, in: event)
    }

    func removeFromDraft(_ adultIDs: Set<Adult.ID>) {
        guard let id = selectedYouthID else { return }
        drafts.remove(adultIDs, for: id)
    }

    func setDraftRoom(_ roomID: Room.ID?) {
        guard let id = selectedYouthID else { return }
        drafts.setRoom(roomID, for: id)
    }

    /// Can this adult be made chair of the board drawn up for the selected
    /// youth?
    func canMakeChair(_ adult: Adult) -> Bool {
        guard let event, let youth = selectedYouth else { return false }
        return drafts.canMakeChair(adult, for: youth, in: event)
    }

    func makeChair(_ adultID: Adult.ID) {
        guard let event, let youth = selectedYouth, let adult = event.adult(id: adultID) else { return }
        drafts.makeChair(adult, for: youth, in: event)
    }

    /// Clicking a room selects it, and the youth in it if any.
    /// A free room has no youth, so the youth selected before is let go:
    /// the inspector and Next Step must not go on acting on someone the
    /// operator has clicked away from.
    /// Return in the search on the Event page (SPEC.md D-21): open the first
    /// room found, or the youth found if they are in no room.
    func openFirstFound() {
        guard let event, page == .event else { return }
        let find = event.find(searchText)
        if let room = find.rooms.first, !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            selectRoom(room.id)
        } else if let youth = find.people.first(where: \.isYouth) {
            selectYouth(youth.id)
        }
    }

    func selectRoom(_ id: Room.ID) {
        selectedRoomID = id
        let occupant = event?.room(id: id).flatMap { room in
            room.isFree ? nil : event?.scouts.first { $0.room == room.name && !($0.status?.isFinished ?? false) }
        }
        selectYouth(occupant?.id)
    }

    // MARK: - Board actions

    /// Run an event change, turning a refusal into a message rather
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
        present(.seatBoard(scoutID: youth.id))
    }

    /// A youth dropped on a room: seat their board there. False when the
    /// drop is refused, so the dragged youth slides back as the message
    /// says why.
    @discardableResult
    func seat(scoutID: Scout.ID, inRoom roomID: Room.ID) -> Bool {
        guard let event, let youth = event.scout(id: scoutID), let room = event.room(id: roomID) else { return false }
        guard youth.status?.isWaitingForBoard == true else {
            message = Message(title: "\(youth.shownFullName) is not waiting.",
                              text: "Only a youth who is waiting for a board can be seated in a room.")
            return false
        }
        guard room.isFree else {
            message = Message(title: "Room \(room.name) is in use.", text: BoardEvent.roomIsTaken(room))
            return false
        }
        selectYouth(scoutID)
        drafts.setRoom(roomID, for: scoutID)
        beginSeating()
        return true
    }

    /// Seat Board's sheet, which shows a refusal inside itself.
    func seat(scoutID: String, roomID: String, chairID: String, memberIDs: [String]) throws {
        try changeBoardOrThrow(scoutID, "Seat Board") { event in
            try event.seatBoard(roomID: roomID, scoutID: scoutID, chairID: chairID, memberIDs: memberIDs)
        }
        drafts.discard(scoutID)
        selectedRoomID = roomID
        attention.askPermissionIfNeeded()
    }

    var canChangeMembers: Bool {
        let status = selectedYouth?.status
        return status == .seated || status == .inProgress
    }

    func beginChangingMembers() {
        guard let youth = selectedYouth, canChangeMembers else { return }
        present(.changeMembers(scoutID: youth.id))
    }

    /// Change Members' sheet, which shows a refusal inside itself.
    func changeMembers(scoutID: String, chairID: String, memberIDs: [String]) throws {
        try changeBoardOrThrow(scoutID, "Change Members") { event in
            try event.changeMembers(scoutID: scoutID, chairID: chairID, memberIDs: memberIDs)
        }
    }

    func confirmStartReview() {
        guard let event, let youth = selectedYouth else { return }
        // A board of review starts with an introduction (SPEC.md D-23): name
        // whom to fetch and where. A project review has none, so it starts at
        // once, as on Windows; Undo takes it back, so there is nothing to
        // confirm (O-2).
        guard AdultLocator.introduction(for: youth, among: event.adults) != nil else {
            startReview(youth)
            return
        }
        let fetch = AdultLocator.introductionText(for: youth, among: event.adults)
        present(Confirmation(
            title: "Start \(youth.shownFullName)'s review?",
            message: "Bring \(youth.shownFullName) into room \(youth.room) and start the review. Do this once the board has "
                + "finished reading the application, references and project workbook.\(fetch)",
            actionTitle: "Start Review"
        ) { [weak self] in
            self?.startReview(youth)
        })
    }

    private func startReview(_ youth: Scout) {
        changeBoard(youth.id, "Start Review", failure: "Could Not Start \(youth.shownFullName)'s Review") { event in
            try event.startReview(scoutID: youth.id)
        }
    }

    func beginCompleting() {
        guard let youth = selectedYouth, youth.status == .inProgress else { return }
        present(.completeBoard(scoutID: youth.id))
    }

    /// Complete's sheet, which shows a refusal inside itself.
    func complete(scoutID: String, result: BoardResult, notes: String) throws {
        try changeBoardOrThrow(scoutID, "Complete") { event in
            try event.completeBoard(scoutID: scoutID, result: result, notes: notes)
        }
    }

    var canPostpone: Bool { selectedYouth?.status?.isWaitingForBoard == true }

    /// Put the selected youth's board off to another event. Undo brings them
    /// back to the waiting list.
    func postpone() {
        guard let youth = selectedYouth, canPostpone else { return }
        if changeBoard(youth.id, "Postpone", failure: "Could Not Postpone \(youth.shownFullName)'s Board", { event in
            try event.postponeBoard(scoutID: youth.id)
        }) {
            drafts.discard(youth.id)
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
        if changeBoard(youth.id, "Reset Board", failure: "Could Not Reset \(youth.shownFullName)'s Board", { event in
            try event.resetBoard(scoutID: youth.id)
        }) {
            selectYouth(youth.id)
        }
    }

    /// The inspector lists who introduces the youth, then their leader and
    /// parents, with where each one is. Show it, scrolled to them, in the
    /// scheduler window even if it was closed.
    func locateSelectedYouth() {
        guard selectedYouth != nil else { return }
        openScheduler()
        showsInspector = true
        locateRequested = true
    }

    // MARK: - Attention

    // The Dock badge and the overdue notifications (SPEC.md P-5) follow the
    // open event, not a window: the sign-in station keeps serving with the
    // scheduler closed, which is when they are most needed.

    @ObservationIgnored let attention = Attention()
    @ObservationIgnored private var roomCheck: Task<Void, Never>?

    var waitingCount: Int {
        event?.scouts.filter { $0.status?.isWaitingForBoard == true }.count ?? 0
    }

    /// From the time the event opens, look for overdue rooms at the top of
    /// every minute, when the room timers go up (D-15). Not the moment it
    /// opens: at launch the app may not be in front yet, and every room
    /// already overdue would be announced as if it had just gone over.
    private func startCheckingRooms() {
        roomCheck?.cancel()
        roomCheck = Task { [weak self] in
            while (try? await Task.sleep(for: .seconds(Timestamp.nextMinute(after: Date()).timeIntervalSinceNow))) != nil,
                  let self {
                checkRoomTimers()
            }
        }
    }

    private func checkRoomTimers() {
        guard let event else { return }
        attention.checkRooms(in: event, now: Date())
    }

    /// The number waiting, on the Dock icon the moment it changes: a youth
    /// signs in, is seated or is put back, or another event is opened.
    private func showWaitingOnTheDock() {
        let count = withObservationTracking { waitingCount } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.showWaitingOnTheDock() }
        }
        attention.showWaiting(count)
    }

    // MARK: - Undo

    /// The scheduler window's undo manager, which Edit › Undo uses while the
    /// window is in front. Set by the window.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Take one step of a youth's board, and let Undo put it back with
    /// `BoardEvent.restoreBoard`. A refusal is shown in an alert.
    @discardableResult
    private func changeBoard(_ scoutID: Scout.ID, _ name: String, failure: String, _ step: (BoardEvent) throws -> Void) -> Bool {
        guard event?.scout(id: scoutID) != nil else { return false }
        return attempt(failure) { try changeBoardOrThrow(scoutID, name, step) }
    }

    /// The same for a step taken in a sheet, which shows the refusal inside
    /// itself: an alert would wait behind the sheet until it closed, and the
    /// sheet's button would seem to do nothing.
    private func changeBoardOrThrow(_ scoutID: Scout.ID, _ name: String, _ step: (BoardEvent) throws -> Void) throws {
        guard let event, let before = event.scout(id: scoutID) else {
            throw EventError("That youth is no longer on the list.")
        }
        try step(event)
        guard let after = event.scout(id: scoutID) else { return }
        registerUndo(name, on: event,
                     undo: { try $0.restoreBoard(before) },
                     redo: { try $0.restoreBoard(after) },
                     reveal: { $0.selectYouth(scoutID) })
    }

    /// Make a change that has a plain inverse, and let Undo apply it.
    @discardableResult
    private func change(_ name: String, failure: String,
                        _ forward: @escaping (BoardEvent) throws -> Void,
                        undo backward: @escaping (BoardEvent) throws -> Void,
                        reveal: @escaping (AppModel) -> Void = { _ in }) -> Bool {
        guard let event, attempt(failure, { try forward(event) }) else { return false }
        registerUndo(name, on: event, undo: backward, redo: forward, reveal: reveal)
        return true
    }

    /// Register `undo`, which when run registers `redo` in turn. A refusal
    /// -- the room has been given to another board since, say -- is shown,
    /// and the step stays as it is.
    private func registerUndo(_ name: String, on event: BoardEvent,
                              undo: @escaping (BoardEvent) throws -> Void,
                              redo: @escaping (BoardEvent) throws -> Void,
                              reveal: @escaping (AppModel) -> Void = { _ in }) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            let undoing = model.undoManager?.isUndoing ?? true
            guard model.event === event,
                  model.attempt("Could Not \(undoing ? "Undo" : "Redo") \(name)", { try undo(event) }) else { return }
            model.registerUndo(name, on: event, undo: redo, redo: undo, reveal: reveal)
            model.tidySelection()
            reveal(model)
        }
        undoManager.setActionName(name)
    }

    /// An undone or redone room change selects the room, while it is there,
    /// so the operator sees what changed on the Event or Rooms page.
    private static func revealRoom(_ id: Room.ID) -> (AppModel) -> Void {
        { model in
            if model.event?.room(id: id) != nil { model.selectedRoomID = id }
        }
    }

    /// After an undo, let go of anything that is no longer there.
    private func tidySelection() {
        guard let event else { return }
        if let id = selectedRoomID, event.room(id: id) == nil { selectedRoomID = nil }
        selectedAdultIDs = selectedAdultIDs.filter { event.adult(id: $0) != nil }
        drafts.forgetRooms(missingFrom: event)
    }

    // MARK: - Adults

    /// Disable stands the selected adults down for the event; Enable brings
    /// them back. Undo reverses either.
    func setAvailable(_ available: Bool) {
        let ids = selectedAdults.filter { available ? $0.isDisabledForToday : $0.isAvailable }.map(\.id)
        guard let event, !ids.isEmpty else { return }
        let names = ids.compactMap { event.adult(id: $0)?.shownFullName }.joined(separator: ", ")
        let apply: (Bool) -> (BoardEvent) throws -> Void = { value in
            { event in for id in ids { try event.setAvailable(value, adultID: id) } }
        }
        if change(available ? "Enable" : "Disable", failure: "Could Not \(available ? "Enable" : "Disable") \(names)",
                  apply(available), undo: apply(!available)), !available {
            drafts.takeOff(Set(ids))
        }
    }

    var canEnableSelectedAdults: Bool { selectedAdults.contains(where: \.isDisabledForToday) }
    var canDisableSelectedAdults: Bool { selectedAdults.contains(where: \.isAvailable) }

    /// The one selected adult, for commands that take a single person.
    var singleSelectedAdult: Adult? {
        let adults = selectedAdults
        return adults.count == 1 ? adults.first : nil
    }

    /// Link the selected adult to the selected youth as the one who
    /// introduces them (SPEC.md D-23), or unlink them -- for the adult who did not check the
    /// youth at sign-in. Start Review names them from then on. Works for an
    /// adult on a board too: a Scoutmaster often is by then.
    func toggleSupportLink() {
        guard let adult = singleSelectedAdult, let youth = selectedYouth else { return }
        setSupporting(!adult.supports(youth.id), adultID: adult.id, scoutID: youth.id)
    }

    func setSupporting(_ linked: Bool, adultID: Adult.ID, scoutID: Scout.ID) {
        let adult = event?.adult(id: adultID)?.shownFullName ?? "the Adult"
        let youth = event?.scout(id: scoutID)?.shownFullName ?? "the Youth"
        change(linked ? "Link Introducer" : "Unlink Introducer",
               failure: linked ? "Could Not Link \(adult) to \(youth)" : "Could Not Unlink \(adult) from \(youth)",
               { try $0.setSupporting(linked, adultID: adultID, scoutID: scoutID) },
               undo: { try $0.setSupporting(!linked, adultID: adultID, scoutID: scoutID) })
    }

    // MARK: - Rooms

    func addRoom(named name: String, boardType: BoardType) throws {
        guard let event else { return }
        let id = try event.addRoom(named: name, boardType: boardType)
        guard let added = event.room(id: id) else { return }
        // Redo puts back this record, ID and all, so the next Undo removes
        // the same room.
        registerUndo("Add Room", on: event,
                     undo: { try $0.removeRoom(id: id) },
                     redo: { try $0.restoreRoom(added) },
                     reveal: Self.revealRoom(id))
    }

    /// Add an earlier event's rooms, empty. Undo removes the rooms it added.
    func copyRooms(from earlier: String) {
        guard let event else { return }
        var copied: [Room.ID] = []
        guard attempt("Could Not Copy the Rooms from \(earlier)", { copied = try event.copyRooms(fromEvent: earlier) }),
              !copied.isEmpty
        else { return }
        let added = copied
        registerUndo("Copy Rooms", on: event,
                     undo: { event in
                         // Rooms in use first: one given a board since refuses
                         // before any room is removed.
                         let rooms = added.compactMap { event.room(id: $0) }
                         for room in rooms.filter({ !$0.isFree }) + rooms.filter(\.isFree) {
                             try event.removeRoom(id: room.id)
                         }
                     },
                     redo: { _ = try $0.copyRooms(fromEvent: earlier) })
    }

    /// Remove the selected room. It must be free. Undo adds it back.
    func removeSelectedRoom() {
        guard let room = selectedRoom else { return }
        guard room.isFree else {
            message = Message(title: "Room \(room.name) is in use.", text: BoardEvent.roomHasABoard(room.name))
            return
        }
        if change("Remove Room", failure: "Could Not Remove Room \(room.name)",
                  { try $0.removeRoom(id: room.id) },
                  undo: { try $0.restoreRoom(room) },
                  reveal: Self.revealRoom(room.id)) {
            tidySelection()
        }
    }

    /// Rename a room, for the Rename sheet. The room keeps its ID.
    func renameRoom(_ id: Room.ID, to newName: String) throws {
        guard let event, let oldName = event.room(id: id)?.name else { return }
        try event.renameRoom(id: id, to: newName)
        // Renaming a room to its own name changes nothing, and has nothing to undo.
        guard event.room(id: id)?.name != oldName else { return }
        registerUndo("Rename Room", on: event,
                     undo: { try $0.renameRoom(id: id, to: oldName) },
                     redo: { try $0.renameRoom(id: id, to: newName) },
                     reveal: Self.revealRoom(id))
    }

    /// Move a board to another room, or swap two boards, for the Move Board
    /// sheet, which shows a refusal inside itself. Swapping again undoes it,
    /// and selects the room the board was moved from; a redo selects the one
    /// it went to, as the move did.
    func swapRooms(_ firstID: Room.ID, _ secondID: Room.ID) throws {
        guard let event else { return }
        let swap: (BoardEvent) throws -> Void = { try $0.swapRooms(firstID, secondID) }
        try swap(event)
        registerUndo("Move Board", on: event, undo: swap, redo: swap, reveal: { model in
            model.selectedRoomID = model.undoManager?.isUndoing == true ? firstID : secondID
        })
        selectedRoomID = secondID
    }

    func setBoardType(_ boardType: BoardType, forRoom roomID: Room.ID) {
        guard let room = event?.room(id: roomID), let old = room.boardType, old != boardType else { return }
        change("Change Room Use", failure: "Could Not Change Room \(room.name)",
               { try $0.setBoardType(boardType, forRoom: roomID) },
               undo: { try $0.setBoardType(old, forRoom: roomID) },
               reveal: Self.revealRoom(roomID))
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
        guard let event else { return }
        guard signUpGeniusAllowed else {
            message = Message(title: "SignUpGenius is off.",
                              text: "SignUpGenius is off while EAGLEBOARDS_DATA_FOLDER is set. Set EAGLEBOARDS_SIGNUPGENIUS=1 to use it.")
            return
        }
        guard let key = SignUpGeniusKeychain.read() else {
            message = Message(title: "No SignUpGenius Key", text: "Add your SignUpGenius API key in Settings first.")
            return
        }
        isImporting = true
        defer { isImporting = false }
        let client = SignUpGeniusClient(apiKey: key)
        do {
            let signup = try await client.findActiveSignup(today: event.date)
            let entries = try await client.filledSlots(signupID: signup.id)
            let summary = try event.mergeSignUps(entries, month: String(event.date.prefix(7)))
            showImportReport(Message(title: "Imported \(signup.title)", text: summary.report))
        } catch {
            showImportReport(Message(title: "Could Not Import Sign-Ups from SignUpGenius", text: error.localizedDescription))
        }
    }

    /// The import reports whenever SignUpGenius answers. A message still
    /// unread then, such as the new adult history on the open that started
    /// the import, keeps its place, with the report below it.
    private func showImportReport(_ report: Message) {
        guard let earlier = message else {
            message = report
            return
        }
        message = Message(title: earlier.title, text: "\(earlier.text)\n\n\(report.title)\n\(report.text)")
    }

    // MARK: - Records, edited in place

    /// Sign an adult in by hand, as the tablet would, and select them if
    /// the Adults page is shown; elsewhere the Adult menu would act on them
    /// unseen. Like a sign-in at the door, it is not undone; Delete Adult
    /// takes a mistake off the event's list.
    func addAdult(_ form: [String: String]) throws {
        guard let event else { return }
        let adult = try event.registerAdult(form)
        if page == .adults { selectedAdultIDs = [adult.id] }
    }

    /// Sign adults in for today straight from the Adult History CSV page, with
    /// the details and roles on file, as if each had signed in at the tablet.
    func signInFromHistory(_ ids: Set<Adult.ID>) {
        guard let event else { return }
        for known in event.adultHistory where ids.contains(known.id) {
            attempt("Could Not Sign In \(known.shownFullName)") {
                _ = try event.registerAdult(Adult.handSignInForm(
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
        guard let event, var record = (scheduled ? event.scheduledScouts : event.scouts).first(where: { $0.id == id }) else {
            return false
        }
        let name = record.shownFullName
        edit(&record)
        return attempt("Could Not Change \(name)") { try event.updateYouth(record, scheduled: scheduled) }
    }

    /// Save a cell changed on the Adults page: promoting someone to Chair,
    /// say. Off the Undo stack, as `editYouth`; the adult history follows.
    @discardableResult
    func editAdult(_ id: Adult.ID, _ edit: (inout Adult) -> Void) -> Bool {
        guard let event, var record = event.adult(id: id) else { return false }
        let name = record.shownFullName
        edit(&record)
        return attempt("Could Not Change \(name)") { try event.updateAdult(record) }
    }

    /// The Rooms page's Board Type cell: off the Undo stack like any cell
    /// (P-6). Room › Used For, an Event page step, is undoable.
    @discardableResult
    func editRoomType(_ id: Room.ID, to boardType: BoardType) -> Bool {
        guard let event else { return false }
        let name = event.room(id: id)?.name ?? id
        return attempt("Could Not Change Room \(name)") { try event.setBoardType(boardType, forRoom: id) }
    }

    /// A deleted record leaves the file and Undo cannot bring it back, so
    /// this one asks first.
    func confirmDeleteYouth(_ id: Scout.ID, scheduled: Bool = false) {
        guard let event, let youth = (scheduled ? event.scheduledScouts : event.scouts).first(where: { $0.id == id }) else {
            return
        }
        present(Confirmation(
            title: "Delete \(youth.shownFullName)?",
            message: "The record is removed from the file. This cannot be undone.",
            actionTitle: "Delete",
            isDestructive: true
        ) { [weak self] in
            guard let self, attempt("Could Not Delete \(youth.shownFullName)", { try event.deleteYouth(id: id, scheduled: scheduled) })
            else { return }
            if !scheduled && selectedYouthID == id { selectYouth(nil) }
        })
    }

    func confirmDeleteAdult(_ id: Adult.ID) {
        guard let event, let adult = event.adult(id: id) else { return }
        present(Confirmation(
            title: "Delete \(adult.shownFullName)?",
            message: "They are taken off today's list; the adult history keeps them. This cannot be undone.",
            actionTitle: "Delete",
            isDestructive: true
        ) { [weak self] in
            guard let self, attempt("Could Not Delete \(adult.shownFullName)", { try event.deleteAdult(id: id) }) else { return }
            selectedAdultIDs.remove(id)
            drafts.takeOff([id])
        })
    }

    // MARK: - Files

    /// Save the page's list as a spreadsheet, with the data files' columns
    /// but never a youth's birthdate or phone number (SPEC.md D-7, D-8).
    func exportList() {
        guard let event, page.isList else { return }
        let text = switch page {
        case .event, .results, .approvedProposals: ""
        case .rooms: CSVFile.render(event.rooms)
        case .youth: CSVFile.render(event.scouts.map(\.forExport))
        case .preRegistered: CSVFile.render(event.scheduledScouts.map(\.forExport))
        case .adults: CSVFile.render(event.adults)
        case .adultHistory: CSVFile.render(event.adultHistory)
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(page.exportName) \(event.date).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "This list holds personal information. Keep the file somewhere private."
        run(panel) { [weak self] url in self?.save(Reports.forSpreadsheet(text), to: url) }
    }

    func exportReport() {
        guard let event else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Board Results \(event.date).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "The report holds names and contact details, including those of minors. Keep it somewhere private."
        run(panel) { [weak self] url in
            self?.save(Reports.forSpreadsheet(Reports.csv(event.scouts, columns: Reports.boardResultColumns)), to: url)
        }
    }

    private func save(_ text: String, to url: URL) {
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            message = Message(title: "Could Not Save “\(url.lastPathComponent)”", text: error.localizedDescription)
        }
    }

    /// The scheduler's window, for the save and open panels to slide down
    /// from. Set by the window.
    @ObservationIgnored weak var schedulerWindow: NSWindow?

    /// Show a save or open panel as a sheet on the scheduler window, brought
    /// forward, as every other prompt there is. It is app-modal only when the
    /// window is closed, or has a sheet up that it would wait behind.
    private func run(_ panel: NSSavePanel, then use: @escaping @MainActor (URL) -> Void) {
        let window = schedulerWindow.flatMap { $0.isVisible ? $0 : nil }
        // The menus still work under a panel sheet, so a second Export or
        // Choose would open app-modal over the first: show the first instead.
        if let window, window.attachedSheet is NSSavePanel {
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let window, window.attachedSheet == nil else {
            if panel.runModal() == .OK, let url = panel.url { use(url) }
            return
        }
        window.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { use(url) }
        }
    }

    func showDataFolderInFinder() {
        guard let event else { return }
        NSWorkspace.shared.activateFileViewerSelecting([event.folder.eventFolder(event.date)])
    }

    func chooseDataFolderWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder for Eagle Boards data. If you used the Java Eagle Board Scheduler, "
            + "choose the folder it ran in, the one holding Master_AdultHistory.csv and the dated folders."
        // Beside the folder in use, so it and its neighbors are in view.
        panel.directoryURL = dataFolder?.root.deletingLastPathComponent()
        run(panel) { [weak self] url in self?.chooseDataFolder(url) }
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
