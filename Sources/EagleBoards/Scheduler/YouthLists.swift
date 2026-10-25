import EagleBoardsCore
import SwiftUI

/// Every youth, in one list stacked by status (SPEC.md O-3): Waiting in
/// sign-in order, On a Board by room, Finished with the most recent first,
/// each headed with its count. Nothing is chosen to see a group. The list has
/// no find of its own: it is short enough to read, and the search finds a
/// person's room over the room cards instead (D-21).
///
/// Double-click or Return takes the next step. A waiting youth can be dragged
/// onto a free room to seat their board there.
struct YouthList: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent

    var body: some View {
        let found = event.scouts
        let selection = Binding(get: { model.selectedYouthID }, set: { model.selectYouth($0) })

        TimelineView(.everyMinute) { timeline in
            List(selection: selection) {
                section(.waiting, of: found, now: timeline.date)
                section(.onBoard, of: found, now: timeline.date)
                section(.finished, of: found, now: timeline.date)
            }
            .accessibilityLabel("Youth")
        }
        .contextMenu(forSelectionType: Scout.ID.self) { ids in
            if let id = ids.first {
                YouthActionButtons(model: model, scoutID: id, inContextMenu: true)
            }
        } primaryAction: { ids in
            guard let id = ids.first else { return }
            model.selectYouth(id)
            model.performNextStep()
        }
        .overlay {
            if event.scouts.isEmpty {
                ContentUnavailableView("No Youth Yet", systemImage: "person.crop.circle.badge.clock",
                                       description: Text("Youth appear here the moment they sign in at the tablet."))
            }
        }
    }

    @ViewBuilder
    private func section(_ group: QueueGroup, of found: [Scout], now: Date) -> some View {
        let rows = group.sorted(found.filter(group.holds))
        Section {
            if rows.isEmpty {
                Text(group.emptyText)
                    .foregroundStyle(.secondary)
            }
            // A list row is dragged through its item provider; .draggable on
            // the row's view starts a drag no room card accepts.
            ForEach(rows) { youth in
                YouthRow(event: event, youth: youth, now: now)
                    .itemProvider {
                        group == .waiting ? NSItemProvider(object: DragPayload.youth(youth.id) as NSString) : nil
                    }
            }
        } header: {
            HStack {
                Text(group.title)
                Spacer()
                Text("\(rows.count)").monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .heading(.h2)
        }
    }
}

/// The list's three groups, in the order they are stacked.
enum QueueGroup {
    case waiting
    case onBoard
    case finished

    var title: String {
        switch self {
        case .waiting: "Waiting"
        case .onBoard: "On a Board"
        case .finished: "Finished"
        }
    }

    var emptyText: String {
        switch self {
        case .waiting: "No one waiting"
        case .onBoard: "No boards sitting"
        case .finished: "Nothing finished yet"
        }
    }

    func holds(_ youth: Scout) -> Bool {
        switch self {
        case .waiting: youth.status?.isWaitingForBoard ?? true
        case .onBoard: youth.status == .seated || youth.status == .inProgress
        case .finished: youth.status?.isFinished ?? false
        }
    }

    /// Waiting in sign-in order, a board by its room, finished the most
    /// recent first.
    func sorted(_ rows: [Scout]) -> [Scout] {
        switch self {
        case .waiting: rows.sorted { $0.queueOrder < $1.queueOrder }
        case .onBoard: rows.sorted { $0.room.localizedStandardCompare($1.room) == .orderedAscending }
        case .finished: rows.sorted { $0.minutesSortKey < $1.minutesSortKey }
        }
    }
}

/// One youth: their name, then sign-in number, unit, and board type or room;
/// on the right, how long they have waited, or the board's status and timer,
/// or how it ended. VoiceOver reads the name, then where they are in words
/// and the second line with commas for its dots.
private struct YouthRow: View {
    let event: BoardEvent
    let youth: Scout
    let now: Date

    var body: some View {
        let minutes = youth.minutesSinceLastUpdate(now: now)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(youth.shownFullName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // The status pill and timer keep their size in a narrow list; the
            // name gives way instead, rather than the pill wrapping to two lines.
            trailing(minutes)
                .fixedSize()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(youth.shownFullName)
        .accessibilityValue(youth.queueValue(minutes: minutes, timer: timer(minutes)))
        // On the whole row, so it shows on keyboard focus too.
        .help(youth.queueHelp(minutes: minutes))
    }

    private func timer(_ minutes: Int?) -> RoomTimer.State? {
        minutes.flatMap { RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: $0, config: event.config) }
    }

    private var detail: String {
        var parts = [youth.regNum, youth.unitDisplay]
        if youth.status == .seated || youth.status == .inProgress {
            parts.append("Room \(youth.room)")
        } else {
            parts.append(youth.boardType?.label ?? youth.boardTypeText)
        }
        if youth.status == .completed, let result = BoardResult(rawValue: youth.result) {
            parts.append(result.label)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private func trailing(_ minutes: Int?) -> some View {
        if youth.status?.isWaitingForBoard ?? true {
            if let minutes {
                Text("\(minutes) min")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else if youth.status?.isFinished == true {
            StatusBadge(statusText: youth.statusText)
        } else {
            HStack(spacing: 6) {
                StatusBadge(statusText: youth.statusText)
                if let minutes, let state = timer(minutes) {
                    TimerBadge(minutes: minutes, state: state)
                }
            }
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
///
/// The context menu lists only what applies, in three groups: the next step
/// first, with the board's members and the adults to fetch; the board being
/// drawn up; then Reset Board and Postpone.
struct YouthActionButtons: View {
    let model: AppModel
    /// Nil acts on the selected youth.
    var scoutID: Scout.ID?
    var inContextMenu = false

    var body: some View {
        let youth = scoutID.flatMap { model.event?.scout(id: $0) } ?? model.selectedYouth
        let status = youth?.status
        // A sheet up is about this board or a room: a step, a reset, or a
        // postponement now would change it under the sheet.
        let idle = model.sheet == nil
        let waiting = status?.isWaitingForBoard == true
        let canReset = idle && (status == .seated || status == .inProgress || status == .verified)
        let canPostpone = idle && waiting

        step(.seat, status: status, idle: idle) { model.beginSeating() }
        step(.startReview, status: status, idle: idle) { model.confirmStartReview() }
        step(.complete, status: status, idle: idle) { model.beginCompleting() }
        command("Change Members…", applies: idle && (status == .seated || status == .inProgress)) {
            model.beginChangingMembers()
        }
        if inContextMenu {
            locate(youth)
        }
        if !inContextMenu || (youth != nil && waiting) {
            Divider()
        }
        command("Start Over", applies: waiting) { model.suggestBoard() }
        command("Fill the Rest", applies: waiting) { model.fillDraft() }
        command("Clear Board", applies: waiting) { model.clearDraft() }
        if !inContextMenu {
            Divider()
            // The Results and Youth pages' double-click, in the menu bar, for
            // a youth the page lists: Results leaves out those still waiting,
            // whom the Event page may have selected.
            let listed = model.page == .youth || (model.page == .results && status?.isWaitingForBoard == false)
            command("Show on Event Page", applies: youth != nil && listed) {
                if let youth {
                    model.openScheduler()
                    model.showOnEventPage(youth.id)
                }
            }
            locate(youth)
        }
        if !inContextMenu || ((youth != nil || waiting) && (canReset || canPostpone)) {
            Divider()
        }
        command("Reset Board", applies: canReset) { model.reset() }
        command("Postpone", applies: canPostpone) { model.postpone() }
    }

    /// Seat Board, Start Review or Complete, on Command-Return while it is
    /// the youth's next step.
    private func step(
        _ step: BoardStep, status: BoardStatus?, idle: Bool, _ action: @escaping @MainActor () -> Void
    ) -> MenuCommand {
        let isNext = status?.nextStep == step
        return command(step.title, applies: idle && isNext,
                       shortcut: isNext ? KeyboardShortcut(.return, modifiers: .command) : nil, action)
    }

    private func locate(_ youth: Scout?) -> MenuCommand {
        command("Locate Leader and Parents", applies: youth != nil, shortcut: KeyboardShortcut("l")) {
            model.locateSelectedYouth()
        }
    }

    private func command(
        _ title: String, applies: Bool, shortcut: KeyboardShortcut? = nil, _ action: @escaping @MainActor () -> Void
    ) -> MenuCommand {
        MenuCommand(title, applies: applies, shortcut: shortcut, inContextMenu: inContextMenu) { run(action) }
    }

    private func run(_ action: () -> Void) {
        if let scoutID, scoutID != model.selectedYouthID {
            model.selectYouth(scoutID)
        }
        action()
    }
}

extension Scout {
    /// Ascending means the most recently changed first.
    var minutesSortKey: Double {
        -(Timestamp.date(fromRecordStamp: lastUpdateTime)?.timeIntervalSince1970 ?? 0)
    }

    var statusRank: Int { status?.sortRank ?? -1 }
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
