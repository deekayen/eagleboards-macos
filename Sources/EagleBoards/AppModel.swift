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
        // A laptop that dozes off mid-evening takes the sign-in station with
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

    /// What the scheduler window's sidebar has chosen to list.
    enum Section: Hashable {
        case waiting
        case onBoards
        case finished
        case adults
        case rooms
        case room(Room.ID)

        /// Does this youth belong in this list?
        func lists(_ youth: Scout) -> Bool {
            switch self {
            case .waiting: youth.status?.isWaitingForBoard ?? true
            case .onBoards: youth.status == .seated || youth.status == .inProgress
            case .finished: youth.status?.isFinished ?? false
            case .adults, .rooms, .room: false
            }
        }
    }

    var section: Section = .waiting
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
        case completeBoard(scoutID: String)
        case addRoom
        case swapRooms(roomID: String)
        case renameRoom(roomID: String)
        case openNight

        var id: String {
            switch self {
            case .seatBoard(let scoutID): "seat \(scoutID)"
            case .completeBoard(let scoutID): "complete \(scoutID)"
            case .addRoom: "add room"
            case .swapRooms(let roomID): "swap \(roomID)"
            case .renameRoom(let roomID): "rename \(roomID)"
            case .openNight: "open night"
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

    /// Show a list in the main window. A room shows every room with that one
    /// selected, and the youth in it.
    func show(_ newSection: Section) {
        section = newSection
        if case .room(let roomID) = newSection {
            selectRoom(roomID)
        }
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

    /// Throw away any changes and propose a board afresh.
    func suggestBoard() {
        guard let night, let youth = selectedYouth, youth.status?.isWaitingForBoard == true else { return }
        drafts[youth.id] = proposedBoard(for: youth, in: night)
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

    /// Empty the board, keeping its room.
    func clearDraft() {
        guard let id = selectedYouthID, drafts[id] != nil else { return }
        drafts[id]?.memberIDs = []
        drafts[id]?.problems = []
        drafts[id]?.isEdited = true
    }

    private func proposedBoard(for youth: Scout, in night: EventNight) -> BoardDraft {
        // The other waiting youth in queue order (pre-registered first), so
        // the proposal keeps chairs and adults free for the boards to come.
        let waiting = night.scouts
            .filter { $0.id != youth.id && $0.status?.isWaitingForBoard == true }
            .sorted { $0.queueOrder < $1.queueOrder }
        let freeSince = BoardSuggestion.freeSinceTimes(adults: night.adults, scouts: night.scouts)
        let suggestion = BoardSuggestion(
            for: youth, adults: night.adults, rooms: night.rooms, waiting: waiting, freeSince: freeSince)
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
    func selectRoom(_ id: Room.ID) {
        selectedRoomID = id
        if let night, let room = night.room(id: id), !room.isFree,
           let youth = night.scouts.first(where: { $0.room == room.name && !($0.status?.isFinished ?? false) }) {
            selectYouth(youth.id)
        }
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
        guard let night else { return false }
        let seated = attempt("Could not seat the board") {
            try night.seatBoard(roomID: roomID, scoutID: scoutID, chairID: chairID, memberIDs: memberIDs)
        }
        if seated {
            drafts[scoutID] = nil
            selectedRoomID = roomID
        }
        return seated
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
            self?.attempt("Could not start the review") { try night.startReview(scoutID: youth.id) }
        }
    }

    func beginCompleting() {
        guard let youth = selectedYouth, youth.status == .inProgress else { return }
        sheet = .completeBoard(scoutID: youth.id)
    }

    func complete(scoutID: String, result: BoardResult, notes: String) -> Bool {
        guard let night else { return false }
        return attempt("Could not complete the board") {
            try night.completeBoard(scoutID: scoutID, result: result, notes: notes)
        }
    }

    var canPostpone: Bool { selectedYouth?.status?.isWaitingForBoard == true }

    func confirmPostpone() {
        guard let night, let youth = selectedYouth, canPostpone else { return }
        confirmation = Confirmation(
            title: "Postpone \(youth.fullName)'s board?",
            message: "Use this when the paperwork or preparation is not ready. They can come back another night.",
            actionTitle: "Postpone",
            isDestructive: true
        ) { [weak self] in
            if self?.attempt("Could not postpone the board", { try night.postponeBoard(scoutID: youth.id) }) == true {
                self?.drafts[youth.id] = nil
            }
        }
    }

    var canReset: Bool {
        let status = selectedYouth?.status
        return status == .seated || status == .inProgress || status == .verified
    }

    func confirmReset() {
        guard let night, let youth = selectedYouth, canReset else { return }
        confirmation = Confirmation(
            title: "Reset \(youth.fullName)'s board?",
            message: "\(youth.fullName) goes back to waiting, and room \(youth.room) and its members are freed.",
            actionTitle: "Reset",
            isDestructive: true
        ) { [weak self] in
            if self?.attempt("Could not reset the board", { try night.resetBoard(scoutID: youth.id) }) == true {
                self?.selectYouth(youth.id)
            }
        }
    }

    /// The inspector lists who came with the youth and where they are.
    func locateSelectedYouth() {
        guard selectedYouth != nil else { return }
        showsInspector = true
    }

    // MARK: - Adults

    /// Disable stands the selected adults down for the night; Enable brings
    /// them back. Each undoes the other, so neither asks first.
    func setAvailable(_ available: Bool) {
        guard let night else { return }
        for adult in selectedAdults where available ? adult.isDisabledForTonight : adult.isAvailable {
            if attempt(available ? "Could not enable \(adult.fullName)" : "Could not disable \(adult.fullName)", {
                try night.setAvailable(available, adultID: adult.id)
            }), !available {
                for scoutID in drafts.keys { drafts[scoutID]?.memberIDs.removeAll { $0 == adult.id } }
            }
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
        guard let night else { return }
        attempt(linked ? "Could not link" : "Could not unlink") {
            try night.setSupporting(linked, adultID: adultID, scoutID: scoutID)
        }
    }

    // MARK: - Rooms

    func confirmRemoveSelectedRoom() {
        guard let night, let room = selectedRoom else { return }
        guard room.isFree else {
            message = Message(title: "Room \(room.name) is in use",
                              text: "\(room.scoutName)'s board is in room \(room.name). A room in use cannot be removed.")
            return
        }
        confirmation = Confirmation(title: "Remove room \(room.name)?", message: "It can be added again later.", actionTitle: "Remove", isDestructive: true) { [weak self] in
            guard let self else { return }
            if self.attempt("Could not remove the room", { try night.removeRoom(id: room.id) }) {
                self.selectedRoomID = nil
                if self.section == .room(room.id) { self.section = .rooms }
                for scoutID in self.drafts.keys where self.drafts[scoutID]?.roomID == room.id {
                    self.drafts[scoutID]?.roomID = nil
                }
            }
        }
    }

    func setBoardType(_ boardType: BoardType, forRoom roomID: Room.ID) {
        guard let night else { return }
        attempt("Could not change the room") { try night.setBoardType(boardType, forRoom: roomID) }
    }

    /// After a rename the room keeps its record but not necessarily its ID.
    func roomRenamed(from oldID: Room.ID, to newID: Room.ID) {
        if selectedRoomID == oldID { selectedRoomID = newID }
        if section == .room(oldID) { section = .room(newID) }
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

    // MARK: - Files

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
