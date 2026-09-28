import EagleBoardsCore
import SwiftUI

/// Every board of the event and how it went (SPEC.md P-6): each youth who has
/// been seated or postponed, read-only. Records is where one is corrected,
/// and File › Export Board Results saves them as a spreadsheet. Double-click
/// a board to see it on the Event page, beside its room.
struct ResultsList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let night: EventNight
    @State private var sortOrder = [KeyPathComparator(\Scout.queueOrder)]

    var body: some View {
        let rows = night.scouts
            .filter { !($0.status?.isWaitingForBoard ?? true) && matches(model.searchText, $0) }
            .sorted(using: sortOrder)
        let selection = Binding(get: { model.selectedYouthID }, set: { model.selectYouth($0) })

        Table(of: Scout.self, selection: selection, sortOrder: $sortOrder) {
            TableColumn("#", value: \.queueOrder) { youth in
                Text(youth.regNum).help(youth.regNumHelp)
            }
            .width(min: 30, ideal: 36, max: 50)
            TableColumn("Name", value: \.last) { youth in
                Text(youth.fullName)
            }
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
            TableColumn("Room", value: \.room)
                .width(min: 40, ideal: 50, max: 70)
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
            ForEach(rows) { TableRow($0) }
        }
        .contextMenu(forSelectionType: Scout.ID.self) { ids in
            if let id = ids.first {
                Button("Show on Event Page") { model.showOnEventPage(id) }
                Button("Correct in Records") { openWindow(id: WindowID.records) }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                model.showOnEventPage(id)
            }
        }
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView("No Boards Yet", systemImage: "checklist",
                                           description: Text("A board appears here once it is seated, and keeps its result when it is complete."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }

    private func matches(_ search: String, _ youth: Scout) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let result = BoardResult(rawValue: youth.result)?.label ?? youth.result
        return [youth.fullName, youth.unitName, youth.unitLabel, youth.leader, youth.room, youth.regNum,
                youth.boardChair, youth.boardMembers, result, youth.notes]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
