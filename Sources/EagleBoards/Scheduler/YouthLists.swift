import EagleBoardsCore
import SwiftUI

/// The youth the sidebar has chosen: waiting, on boards, or finished. Each
/// list is its own table, since a table's columns cannot change on macOS 14.
///
/// Double-click or Return takes the next step. A waiting youth can be dragged
/// onto a free room to seat their board there.
struct YouthList: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    let section: AppModel.Section

    var body: some View {
        let rows = night.scouts.filter { section.lists($0) && matches(model.searchText, $0) }
        let selection = Binding(get: { model.selectedYouthID }, set: { model.selectYouth($0) })

        TimelineView(.periodic(from: .now, by: 20)) { timeline in
            Group {
                switch section {
                case .onBoards: OnBoardsTable(night: night, rows: rows, now: timeline.date, selection: selection)
                case .finished: FinishedTable(night: night, rows: rows, selection: selection)
                default: WaitingTable(night: night, rows: rows, now: timeline.date, selection: selection)
                }
            }
        }
        .contextMenu(forSelectionType: Scout.ID.self) { ids in
            if let id = ids.first {
                YouthActionButtons(model: model, scoutID: id)
            }
        } primaryAction: { ids in
            guard let id = ids.first else { return }
            model.selectYouth(id)
            model.performNextStep()
        }
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    emptyState
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch section {
        case .onBoards:
            ContentUnavailableView("No Boards Sitting", systemImage: "person.3",
                                   description: Text("Seated boards and reviews in progress are listed here."))
        case .finished:
            ContentUnavailableView("Nothing Finished Yet", systemImage: "checkmark.circle",
                                   description: Text("Completed and postponed boards are listed here."))
        default:
            ContentUnavailableView("No One Waiting", systemImage: "person.crop.circle.badge.clock",
                                   description: Text("Youth appear here the moment they sign in at the tablet."))
        }
    }

    private func matches(_ search: String, _ youth: Scout) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [youth.fullName, youth.unitName, youth.unitLabel, youth.leader, youth.room, youth.regNum, youth.boardChair, youth.boardMembers]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct WaitingTable: View {
    let night: EventNight
    let rows: [Scout]
    let now: Date
    let selection: Binding<Scout.ID?>
    @State private var sortOrder = [KeyPathComparator(\Scout.queueOrder)]

    var body: some View {
        Table(of: Scout.self, selection: selection, sortOrder: $sortOrder) {
            TableColumn("#", value: \.queueOrder) { youth in
                Text(youth.regNum).help(youth.regNumHelp)
            }
            .width(min: 30, ideal: 36, max: 50)
            TableColumn("Waiting", value: \.minutesSortKey) { youth in
                Text(youth.minutesSinceLastUpdate(now: now).map { "\($0) min" } ?? "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60, max: 80)
            TableColumn("Last", value: \.last)
            TableColumn("First", value: \.first)
            TableColumn("Unit", value: \.unitName) { youth in
                Text(youth.unitLabel).help(youth.unitName)
            }
            .width(min: 44, ideal: 60, max: 90)
            TableColumn("Board", value: \.boardTypeText) { youth in
                BoardTypeText(youth: youth)
            }
            .width(min: 50, ideal: 64, max: 90)
            TableColumn("Leader", value: \.leader)
        } rows: {
            ForEach(rows.sorted(using: sortOrder)) { youth in
                TableRow(youth).draggable(DragPayload.youth(youth.id))
            }
        }
    }
}

private struct OnBoardsTable: View {
    let night: EventNight
    let rows: [Scout]
    let now: Date
    let selection: Binding<Scout.ID?>
    @State private var sortOrder = [KeyPathComparator(\Scout.room)]

    var body: some View {
        Table(of: Scout.self, selection: selection, sortOrder: $sortOrder) {
            TableColumn("Room", value: \.room)
                .width(min: 40, ideal: 50, max: 70)
            TableColumn("Time", value: \.minutesSortKey) { youth in
                if let minutes = youth.minutesSinceLastUpdate(now: now),
                   let state = RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: minutes, config: night.config) {
                    TimerBadge(minutes: minutes, state: state)
                }
            }
            .width(min: 50, ideal: 60, max: 80)
            TableColumn("Status", value: \.statusRank) { youth in
                StatusBadge(statusText: youth.statusText)
            }
            .width(min: 70, ideal: 90, max: 110)
            TableColumn("Last", value: \.last)
            TableColumn("First", value: \.first)
            TableColumn("Unit", value: \.unitName) { youth in
                Text(youth.unitLabel).help(youth.unitName)
            }
            .width(min: 44, ideal: 60, max: 90)
            TableColumn("Board", value: \.boardTypeText) { youth in
                BoardTypeText(youth: youth)
            }
            .width(min: 50, ideal: 64, max: 90)
            TableColumn("Chair", value: \.boardChair)
            TableColumn("Members", value: \.boardMembers) { youth in
                Text(youth.boardMembers.withListSeparators).help(youth.boardMembers.withListSeparators)
            }
        } rows: {
            ForEach(rows.sorted(using: sortOrder)) { TableRow($0) }
        }
    }
}

private struct FinishedTable: View {
    let night: EventNight
    let rows: [Scout]
    let selection: Binding<Scout.ID?>
    @State private var sortOrder = [KeyPathComparator(\Scout.queueOrder)]

    var body: some View {
        Table(of: Scout.self, selection: selection, sortOrder: $sortOrder) {
            TableColumn("#", value: \.queueOrder) { youth in
                Text(youth.regNum).help(youth.regNumHelp)
            }
            .width(min: 30, ideal: 36, max: 50)
            TableColumn("Last", value: \.last)
            TableColumn("First", value: \.first)
            TableColumn("Unit", value: \.unitName) { youth in
                Text(youth.unitLabel).help(youth.unitName)
            }
            .width(min: 44, ideal: 60, max: 90)
            TableColumn("Board", value: \.boardTypeText) { youth in
                BoardTypeText(youth: youth)
            }
            .width(min: 50, ideal: 64, max: 90)
            TableColumn("Status", value: \.statusRank) { youth in
                StatusBadge(statusText: youth.statusText)
            }
            .width(min: 70, ideal: 90, max: 110)
            TableColumn("Result", value: \.result) { youth in
                Text(BoardResult(rawValue: youth.result)?.label ?? youth.result)
            }
            .width(min: 60, ideal: 90, max: 120)
            TableColumn("Chair", value: \.boardChair)
            TableColumn("Members", value: \.boardMembers) { youth in
                Text(youth.boardMembers.withListSeparators).help(youth.boardMembers.withListSeparators)
            }
            TableColumn("Notes", value: \.notes) { youth in
                Text(youth.notes.withCommasRestored).help(youth.notes.withCommasRestored)
            }
        } rows: {
            ForEach(rows.sorted(using: sortOrder)) { TableRow($0) }
        }
    }
}

/// "Final" or "Project", with the full name on hover.
struct BoardTypeText: View {
    let youth: Scout

    var body: some View {
        Text(youth.boardType == .projectReview ? "Project" : youth.boardTypeText)
            .help(youth.boardType?.label ?? "")
    }
}

/// What can be done to one youth: the Board menu, and the context menu on
/// their row. Acting on a row that is not selected selects it first, so the
/// inspector shows who the action was for.
struct YouthActionButtons: View {
    let model: AppModel
    /// Nil acts on the selected youth.
    var scoutID: Scout.ID?

    var body: some View {
        let youth = scoutID.flatMap { model.night?.scout(id: $0) } ?? model.selectedYouth
        let status = youth?.status
        let idle = model.sheet == nil

        Button(BoardStep.seat.title) { run { model.beginSeating() } }
            .keyboardShortcut(status?.nextStep == .seat ? KeyboardShortcut(.return, modifiers: .command) : nil)
            .disabled(!idle || status?.nextStep != .seat)
        Button(BoardStep.startReview.title) { run { model.confirmStartReview() } }
            .keyboardShortcut(status?.nextStep == .startReview ? KeyboardShortcut(.return, modifiers: .command) : nil)
            .disabled(!idle || status?.nextStep != .startReview)
        Button(BoardStep.complete.title) { run { model.beginCompleting() } }
            .keyboardShortcut(status?.nextStep == .complete ? KeyboardShortcut(.return, modifiers: .command) : nil)
            .disabled(!idle || status?.nextStep != .complete)
        Button("Change Members…") { run { model.beginChangingMembers() } }
            .disabled(!idle || (status != .seated && status != .inProgress))
        Divider()
        Button("Suggest a Board") { run { model.suggestBoard() } }
            .disabled(status?.isWaitingForBoard != true)
        Button("Clear Board") { run { model.clearDraft() } }
            .disabled(status?.isWaitingForBoard != true)
        Divider()
        Button("Locate Leader and Parents") { run { model.locateSelectedYouth() } }
            .keyboardShortcut("l")
            .disabled(youth == nil)
        Divider()
        Button("Reset Board") { run { model.reset() } }
            .disabled(!(status == .seated || status == .inProgress || status == .verified))
        Button("Postpone") { run { model.postpone() } }
            .disabled(status?.isWaitingForBoard != true)
    }

    private func run(_ action: () -> Void) {
        if let scoutID, scoutID != model.selectedYouthID {
            model.selectYouth(scoutID)
        }
        action()
    }
}

extension Scout {
    /// Pre-registered first, then walk-ins, each in the order they signed in.
    /// Sorting by this keeps someone who booked a slot ahead of a walk-in who
    /// happened to arrive early.
    var queueOrder: String {
        let rank = isPreRegistered ? 0 : isWalkIn ? 1 : 2
        let number = Int(regNum.drop(while: \.isLetter)) ?? 0
        return String(format: "%d-%06d", rank, number)
    }

    /// Ascending means the most recently changed first.
    var minutesSortKey: Double {
        -(Timestamp.date(fromRecordStamp: lastUpdateTime)?.timeIntervalSince1970 ?? 0)
    }

    var statusRank: Int { status?.sortRank ?? -1 }

    var regNumHelp: String {
        let number = regNum.drop(while: \.isLetter)
        if isPreRegistered {
            return "Pre-registered -- matched a sign-up. #\(number) of the pre-registered to sign in."
        }
        if isWalkIn {
            return "Walk-in -- no pre-registration matched. #\(number) of the walk-ins to sign in."
        }
        return ""
    }
}

/// What a drag carries: a youth or an adult, by ID. Plain text, so it needs
/// no registered type; the prefix keeps anything else dropped from counting.
enum DragPayload {
    private static let youthPrefix = "eagleboards-youth:"
    private static let adultPrefix = "eagleboards-adult:"

    static func youth(_ id: Scout.ID) -> String { youthPrefix + id }
    static func adult(_ id: Adult.ID) -> String { adultPrefix + id }

    static func youthIDs(in items: [String]) -> [Scout.ID] {
        items.filter { $0.hasPrefix(youthPrefix) }.map { String($0.dropFirst(youthPrefix.count)) }
    }

    static func adultIDs(in items: [String]) -> [Adult.ID] {
        items.filter { $0.hasPrefix(adultPrefix) }.map { String($0.dropFirst(adultPrefix.count)) }
    }
}
