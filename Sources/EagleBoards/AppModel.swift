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
    private enum Keys {
        static let dataFolderPath = "dataFolderPath"
        static let port = "checkInPort"
        static let importOnOpen = "importSignUpsOnOpen"
    }

    // MARK: - The open night

    private(set) var dataFolder: DataFolder?
    private(set) var night: EventNight?
    var openError: String?

    /// `YYYY-MM-DD` for today, the night opened by default.
    var today: String { Timestamp.dayStamp(for: Date()) }

    init() {
        let environment = ProcessInfo.processInfo.environment
        // For development: point the app at a scratch folder of synthetic data
        // without touching the saved choice. Never point it at real data you
        // are about to screenshot.
        let folderPath = environment["EAGLEBOARDS_DATA_FOLDER"] ?? UserDefaults.standard.string(forKey: Keys.dataFolderPath)
        port = Int(environment["EAGLEBOARDS_PORT"] ?? "") ?? (UserDefaults.standard.object(forKey: Keys.port) as? Int) ?? 8080
        importOnOpen = UserDefaults.standard.object(forKey: Keys.importOnOpen) as? Bool ?? true
        hasSignUpGeniusKey = SignUpGeniusKeychain.exists()
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
            if importOnOpen, name == today, hasSignUpGeniusKey {
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

    var selectedYouthID: Scout.ID?
    /// The adults ticked for the next board, in the order they were ticked.
    var checkedAdultIDs: [Adult.ID] = []
    var selectedAdultID: Adult.ID?
    var selectedRoomID: Room.ID?
    var showFinishedYouth = false
    var showBusyAdults = false
    var roomFilter = ""

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

    struct Notice: Identifiable, Equatable {
        enum Kind { case success, info, problem }
        let id = UUID()
        let title: String
        let lines: [String]
        let kind: Kind
    }

    /// A message that shows for a few seconds and goes away by itself.
    var notice: Notice?
    /// A refusal or failure the operator has to acknowledge.
    var problem: String?

    var selectedYouth: Scout? { selectedYouthID.flatMap { night?.scout(id: $0) } }
    var selectedRoom: Room? { selectedRoomID.flatMap { night?.room(id: $0) } }

    /// Checked adults who can still be seated -- someone checked a moment ago
    /// may have been put on another board since.
    var checkedAdults: [Adult] {
        guard let night else { return [] }
        return checkedAdultIDs.compactMap { night.adult(id: $0) }
    }

    func clearSchedulerSelection() {
        selectedYouthID = nil
        checkedAdultIDs = []
        selectedAdultID = nil
        selectedRoomID = nil
    }

    func setChecked(_ checked: Bool, adultID: String) {
        checkedAdultIDs.removeAll { $0 == adultID }
        if checked {
            checkedAdultIDs.append(adultID)
        }
    }

    /// Selecting a youth proposes a board, the way the Java scheduler did.
    ///
    /// Checked adults are the operator's work in progress -- they have decided
    /// who is sitting this board -- so when anyone is already checked nothing
    /// is changed. Only Clear throws that away.
    func selectYouth(_ id: Scout.ID?) {
        selectedYouthID = id
        guard let id, let night, let youth = night.scout(id: id), checkedAdultIDs.isEmpty else { return }

        switch youth.status {
        case .registered, .verified:
            // The other waiting youth in queue order (pre-registered first), so
            // the proposal keeps chairs and adults free for the boards to come.
            let waiting = night.scouts
                .filter { $0.id != youth.id && $0.status?.isWaitingForBoard == true }
                .sorted { $0.queueOrder < $1.queueOrder }
            let freeSince = BoardSuggestion.freeSinceTimes(adults: night.adults, scouts: night.scouts)
            let suggestion = BoardSuggestion(
                for: youth, adults: night.adults, rooms: night.rooms, waiting: waiting, freeSince: freeSince)
            checkedAdultIDs = suggestion.memberIDs
            selectedRoomID = suggestion.roomID
            if suggestion.problems.isEmpty {
                notice = Notice(title: "Ready to seat", lines: ["\(youth.fullName): check the adults ticked for the board, then press Seat Board."], kind: .success)
            } else {
                notice = Notice(title: "Could not propose a whole board", lines: suggestion.problems, kind: .problem)
            }
        default:
            selectedRoomID = night.room(named: youth.room)?.id
        }
    }

    /// Clicking a room card selects the room, and the youth in it if any.
    func selectRoom(_ id: Room.ID) {
        selectedRoomID = id
        if let night, let room = night.room(id: id), !room.isFree,
           let youth = night.scouts.first(where: { $0.room == room.name && !($0.status?.isFinished ?? false) }) {
            selectedYouthID = youth.id
        }
    }

    // MARK: - Board actions

    /// Run an event-night change, turning a refusal into a message rather
    /// than a silent failure.
    @discardableResult
    func attempt(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    func beginSeating() {
        guard let youth = selectedYouth else { return }
        sheet = .seatBoard(scoutID: youth.id)
    }

    func seat(scoutID: String, roomID: String, chairID: String, memberIDs: [String]) -> Bool {
        guard let night else { return false }
        let seated = attempt {
            try night.seatBoard(roomID: roomID, scoutID: scoutID, chairID: chairID, memberIDs: memberIDs)
        }
        if seated, let youth = night.scout(id: scoutID) {
            checkedAdultIDs = []
            notice = Notice(
                title: "Board seated in room \(youth.room)",
                lines: ["The members have the paperwork. \(youth.fullName) waits outside until Start Review."],
                kind: .success
            )
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
            guard let self else { return }
            if self.attempt({ try night.startReview(scoutID: youth.id) }) {
                self.notice = Notice(title: "Review started", lines: ["\(youth.fullName) in room \(youth.room)"], kind: .success)
            }
        }
    }

    func beginCompleting() {
        guard let youth = selectedYouth else { return }
        sheet = .completeBoard(scoutID: youth.id)
    }

    func complete(scoutID: String, result: BoardResult, notes: String) -> Bool {
        guard let night else { return false }
        let completed = attempt { try night.completeBoard(scoutID: scoutID, result: result, notes: notes) }
        if completed, let youth = night.scout(id: scoutID) {
            var lines = ["\(youth.fullName): \(result.label). The room and the members are free again."]
            let people = AdultLocator.locate(for: youth, among: night.adults)
            if !people.isEmpty {
                lines.append("Let them know:")
                lines += people.map { "\($0.relation.rawValue): \($0.adult.fullName) (\($0.whereabouts))" }
            }
            notice = Notice(title: "Board completed", lines: lines, kind: .success)
        }
        return completed
    }

    func confirmPostpone() {
        guard let night, let youth = selectedYouth else { return }
        confirmation = Confirmation(
            title: "Postpone \(youth.fullName)'s board?",
            message: "Use this when the paperwork or preparation is not ready. They can come back another night.",
            actionTitle: "Postpone",
            isDestructive: true
        ) { [weak self] in
            self?.attempt { try night.postponeBoard(scoutID: youth.id) }
        }
    }

    func confirmReset() {
        guard let night, let youth = selectedYouth else { return }
        confirmation = Confirmation(
            title: "Reset \(youth.fullName)'s board?",
            message: "\(youth.fullName) goes back to waiting, and room \(youth.room) and its members are freed.",
            actionTitle: "Reset",
            isDestructive: true
        ) { [weak self] in
            self?.attempt { try night.resetBoard(scoutID: youth.id) }
        }
    }

    func locateSelectedYouth() {
        guard let night, let youth = selectedYouth else { return }
        let people = AdultLocator.locate(for: youth, among: night.adults)
        if people.isEmpty {
            notice = Notice(
                title: "Could not locate",
                lines: ["\(youth.fullName)'s leader '\(youth.leader)' has not signed in."],
                kind: .problem
            )
        } else {
            let place = youth.room.isEmpty || youth.room == disabledForTonightMarker ? "" : " [room \(youth.room)]"
            notice = Notice(
                title: "\(youth.fullName)\(place)",
                lines: people.map { "\($0.relation.rawValue): \($0.adult.fullName) (\($0.whereabouts))" },
                kind: .info
            )
        }
    }

    // MARK: - Adults

    func confirmAvailability(_ available: Bool) {
        guard let night, let id = selectedAdultID, let adult = night.adult(id: id) else { return }
        confirmation = Confirmation(
            title: available ? "Enable \(adult.fullName)?" : "Disable \(adult.fullName)?",
            message: available
                ? "They can be put on a board again."
                : "They are taken out of the pool for tonight, for example because they have gone home.",
            actionTitle: available ? "Enable" : "Disable"
        ) { [weak self] in
            guard let self else { return }
            if self.attempt({ try night.setAvailable(available, adultID: id) }), !available {
                self.setChecked(false, adultID: id)
            }
        }
    }

    /// Link the selected adult to the selected youth as someone who came to
    /// support them, or unlink them -- for the adult who did not check the
    /// youth at sign-in. Start Review names them from then on. Works for an
    /// adult on a board too: a Scoutmaster often is by then.
    func confirmSupportLink() {
        guard let night, let adultID = selectedAdultID, let adult = night.adult(id: adultID),
              let youth = selectedYouth else { return }
        let linked = adult.supports(youth.id)
        confirmation = Confirmation(
            title: linked ? "Unlink \(adult.fullName)?" : "Link \(adult.fullName)?",
            message: linked
                ? "\(adult.fullName) is linked as supporting \(youth.fullName). Unlink them?"
                : "\(adult.fullName) came to support \(youth.fullName)? Start Review will then say where to find them.",
            actionTitle: linked ? "Unlink" : "Link"
        ) { [weak self] in
            guard let self else { return }
            if self.attempt({ try night.setSupporting(!linked, adultID: adultID, scoutID: youth.id) }) {
                self.notice = Notice(
                    title: linked ? "Unlinked" : "Linked",
                    lines: ["\(adult.fullName) \(linked ? "is no longer linked to" : "is linked to") \(youth.fullName)."],
                    kind: .success)
            }
        }
    }

    // MARK: - Rooms

    func confirmRemoveSelectedRoom() {
        guard let night, let room = selectedRoom else { return }
        guard room.isFree else {
            problem = "Room \(room.name) is in use by \(room.scoutName) and cannot be removed."
            return
        }
        confirmation = Confirmation(title: "Remove room \(room.name)?", message: "It can be added again later.", actionTitle: "Remove", isDestructive: true) { [weak self] in
            if self?.attempt({ try night.removeRoom(id: room.id) }) == true {
                self?.selectedRoomID = nil
            }
        }
    }

    // MARK: - SignUpGenius

    var isImporting = false
    /// Checked once at launch and after each save, rather than on every
    /// redraw: reading the keychain can put up a prompt.
    private(set) var hasSignUpGeniusKey = false

    /// Store the key (or remove it, if empty). Returns whether it was saved.
    func saveSignUpGeniusKey(_ key: String) -> Bool {
        let saved = SignUpGeniusKeychain.write(key)
        hasSignUpGeniusKey = SignUpGeniusKeychain.exists()
        return saved
    }

    func importSignUps() async {
        guard let night else { return }
        guard let key = SignUpGeniusKeychain.read() else {
            problem = "Add your SignUpGenius API key in Settings first."
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
            notice = Notice(title: "Imported \(signup.title)", lines: lines, kind: .success)
        } catch {
            problem = error.localizedDescription
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
            problem = "Could not save the report: \(error.localizedDescription)"
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
