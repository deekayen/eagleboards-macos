import EagleBoardsCore
import SwiftUI

/// Every board that has convened tonight, with its result once there is one.
struct BoardsPanel: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var sortOrder = [KeyPathComparator(\Scout.queueOrder)]

    private static let listedStatuses: Set<BoardStatus> = [.seated, .inProgress, .completed, .postponed]

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Boards", detail: summary) {
                Button("Export Results…") { model.exportReport() }
                    .help("Save every youth's board and result as a spreadsheet (CSV)")
            }
            Table(rows, selection: Binding(get: { model.selectedYouthID }, set: { model.selectYouth($0) }), sortOrder: $sortOrder) {
                // Grouped: a table builder takes at most ten columns at a level.
                Group {
                    TableColumn("#", value: \Scout.queueOrder) { Text($0.regNum) }
                        .width(min: 30, ideal: 36, max: 50)
                    TableColumn("Last", value: \Scout.last)
                    TableColumn("First", value: \Scout.first)
                    TableColumn("Unit", value: \Scout.unitName) { Text($0.unitLabel) }
                        .width(min: 44, ideal: 60, max: 90)
                    TableColumn("Board", value: \Scout.boardTypeText)
                        .width(min: 44, ideal: 56, max: 70)
                    TableColumn("Status", value: \Scout.statusRank) { youth in
                        StatusBadge(statusText: youth.statusText, config: night.config)
                    }
                    .width(min: 70, ideal: 90, max: 110)
                    TableColumn("Room", value: \Scout.room) { youth in
                        Text(youth.room == disabledForTonightMarker ? "" : youth.room)
                    }
                    .width(min: 36, ideal: 48, max: 70)
                }
                TableColumn("Result", value: \Scout.result) { youth in
                    Text(BoardResult(rawValue: youth.result)?.label ?? youth.result)
                }
                .width(min: 60, ideal: 90, max: 120)
                TableColumn("Chair", value: \Scout.boardChair)
                TableColumn("Members", value: \Scout.boardMembers) { youth in
                    Text(youth.boardMembers.withListSeparators).help(youth.boardMembers.withListSeparators)
                }
                TableColumn("Leader", value: \Scout.leader)
                TableColumn("Notes", value: \Scout.notes) { youth in
                    Text(youth.notes.withCommasRestored).help(youth.notes.withCommasRestored)
                }
            }
        }
    }

    private var rows: [Scout] {
        night.scouts
            .filter { $0.status.map(Self.listedStatuses.contains) ?? false }
            .sorted(using: sortOrder)
    }

    private var summary: String {
        let results = night.scouts.filter { $0.status == .completed }
        let approved = results.filter { $0.result == BoardResult.approved.rawValue }.count
        return "\(results.count) completed · \(approved) approved"
    }
}
