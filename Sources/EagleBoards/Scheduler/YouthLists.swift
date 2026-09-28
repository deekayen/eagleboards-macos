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
    let night: EventNight

    var body: some View {
        let found = night.scouts
        let selection = Binding(get: { model.selectedYouthID }, set: { model.selectYouth($0) })

        TimelineView(.periodic(from: .now, by: 20)) { timeline in
            List(selection: selection) {
                section(.waiting, of: found, now: timeline.date)
                section(.onBoard, of: found, now: timeline.date)
                section(.finished, of: found, now: timeline.date)
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
            if night.scouts.isEmpty {
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
                YouthRow(night: night, youth: youth, now: now)
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
/// or how it ended.
private struct YouthRow: View {
    let night: EventNight
    let youth: Scout
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(youth.fullName)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(youth.regNumHelp)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [youth.regNum, youth.unitLabel]
        if youth.status == .seated || youth.status == .inProgress {
            parts.append("Room \(youth.room)")
        } else {
            parts.append(youth.boardType == .projectReview ? "Project" : youth.boardTypeText)
        }
        if youth.status == .completed, let result = BoardResult(rawValue: youth.result) {
            parts.append(result.label)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        let minutes = youth.minutesSinceLastUpdate(now: now)
        if youth.status?.isWaitingForBoard ?? true {
            if let minutes {
                Text("\(minutes) min")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Waiting \(minutes) minutes")
            }
        } else if youth.status?.isFinished == true {
            StatusBadge(statusText: youth.statusText)
        } else {
            HStack(spacing: 6) {
                StatusBadge(statusText: youth.statusText)
                if let minutes,
                   let state = RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: minutes, config: night.config) {
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
