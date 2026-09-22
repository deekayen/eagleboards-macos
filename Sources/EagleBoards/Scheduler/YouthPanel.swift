import EagleBoardsCore
import SwiftUI

/// Youth who have signed in, and the buttons that move a board along.
struct YouthPanel: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var sortOrder = [KeyPathComparator(\Scout.queueOrder)]

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            PanelHeader(title: "Youth", detail: waitingSummary) {
                Toggle("Show Finished", isOn: $model.showFinishedYouth)
                    .toggleStyle(.button)
                    .help("Show youth whose boards are completed or postponed")
            }
            HStack(spacing: 6) {
                lifecycleButtons(inMenu: false)
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .background(.bar)
            TimelineView(.periodic(from: .now, by: 20)) { timeline in
                Table(rows, selection: Binding(get: { model.selectedYouthID }, set: { model.selectYouth($0) }), sortOrder: $sortOrder) {
                    TableColumn("#", value: \.queueOrder) { youth in
                        Text(youth.regNum)
                            .help(regNumHelp(youth))
                    }
                    .width(min: 30, ideal: 36, max: 50)

                    TableColumn("Min", value: \.minutesSortKey) { youth in
                        let minutes = youth.minutesSinceLastUpdate(now: timeline.date)
                        Text(minutes.map(String.init) ?? "")
                            .monospacedDigit()
                            .help(minutesHelp(youth, minutes: minutes))
                    }
                    .width(min: 30, ideal: 36, max: 50)

                    TableColumn("Last", value: \.last)
                    TableColumn("First", value: \.first)
                    TableColumn("Unit", value: \.unitName) { youth in
                        Text(youth.unitLabel).help(youth.unitName)
                    }
                    .width(min: 44, ideal: 60, max: 90)
                    TableColumn("Board", value: \.boardTypeText) { youth in
                        Text(youth.boardType == .projectReview ? "Project" : youth.boardTypeText)
                            .help(youth.boardType?.label ?? "")
                    }
                    .width(min: 44, ideal: 56, max: 70)
                    TableColumn("Room", value: \.room) { youth in
                        Text(youth.room == disabledForTonightMarker ? "" : youth.room)
                    }
                    .width(min: 36, ideal: 48, max: 70)
                    TableColumn("Status", value: \.statusRank) { youth in
                        StatusBadge(statusText: youth.statusText, config: night.config)
                    }
                    .width(min: 70, ideal: 90, max: 110)
                    TableColumn("Leader", value: \.leader)
                }
                .contextMenu(forSelectionType: Scout.ID.self) { _ in
                    lifecycleButtons(inMenu: true)
                }
            }
        }
    }

    private var rows: [Scout] {
        night.scouts
            .filter { model.showFinishedYouth || !($0.status?.isFinished ?? false) }
            .sorted(using: sortOrder)
    }

    private var waitingSummary: String {
        let waiting = night.scouts.filter { $0.status?.isWaitingForBoard == true }.count
        let active = night.scouts.filter { $0.status == .seated || $0.status == .inProgress }.count
        return "\(waiting) waiting · \(active) on boards"
    }

    @ViewBuilder
    private func lifecycleButtons(inMenu: Bool) -> some View {
        let status = model.selectedYouth?.status
        let hasSelection = model.selectedYouth != nil

        Button("Seat Board") { model.beginSeating() }
            .disabled(status?.isWaitingForBoard != true)
            .help("Put the board members in a room to read the application, references and project workbook. The youth stays outside until Start Review.")
        Button("Start Review") { model.confirmStartReview() }
            .disabled(status != .seated)
            .help("Bring the youth into the room and begin the review, once the members are done reading.")
        Button("Complete") { model.beginCompleting() }
            .disabled(status != .inProgress)
            .help("Finish the review and record the result. Available once the youth has been brought in.")
        if inMenu {
            Divider()
        } else {
            ToolbarSeparator()
        }
        Button("Locate") { model.locateSelectedYouth() }
            .disabled(!hasSelection)
            .help("Find this youth's leader and parents among the adults who signed in")
        Button("Reset") { model.confirmReset() }
            .disabled(!(status == .seated || status == .inProgress || status == .verified))
            .help("Undo seating: the youth waits again and the room and members are freed")
        Button("Postpone") { model.confirmPostpone() }
            .disabled(status?.isWaitingForBoard != true)
            .help("Put this board off to another night")
    }

    private func regNumHelp(_ youth: Scout) -> String {
        let number = youth.regNum.drop(while: \.isLetter)
        if youth.isPreRegistered {
            return "Pre-registered -- matched a sign-up. #\(number) of the pre-registered to sign in."
        }
        if youth.isWalkIn {
            return "Walk-in -- no pre-registration matched. #\(number) of the walk-ins to sign in."
        }
        return ""
    }

    private func minutesHelp(_ youth: Scout, minutes: Int?) -> String {
        guard let minutes else { return "" }
        switch youth.status {
        case .seated: return "Board convening for \(minutes) min"
        case .inProgress: return "In review for \(minutes) min"
        case .completed, .postponed: return "\(minutes) min since finishing"
        default: return "Waiting \(minutes) min"
        }
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
}
