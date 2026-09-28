import EagleBoardsCore
import SwiftUI

/// The boards table (SPEC.md P-6): every youth who has been seated or
/// postponed, and how their board went. A result, its notes, a name or a unit
/// is corrected in place; a changed cell is saved as it is left and stays off
/// the Undo stack. The status, who sat on the board and the room are
/// read-only: they change only through the Event page's steps, which take
/// and free a room and its members. File › Export Board Results
/// saves the report. Double-click a board to see it on the Event page.
///
/// A youth's birthdate and phone number are never shown here (D-7, D-8).
struct ResultsPage: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var sortOrder = [KeyPathComparator(\Scout.queueOrder)]

    var body: some View {
        let rows = night.scouts
            .filter { !($0.status?.isWaitingForBoard ?? true) && matches(model.searchText, $0) }
            .sorted(using: sortOrder)
        let selection = Binding(get: { model.selectedYouthID }, set: { model.selectYouth($0) })

        Table(of: Scout.self, selection: selection, sortOrder: $sortOrder) {
            Group {
                TableColumn("#", value: \Scout.queueOrder) { youth in
                    Text(youth.regNum).help(youth.regNumHelp)
                }
                .width(min: 30, ideal: 36, max: 50)
                TableColumn("Last", value: \Scout.last) { youth in
                    EditableText(youth.last, name: "Last name") { value in edit(youth) { $0.last = value } }
                }
                TableColumn("First", value: \Scout.first) { youth in
                    EditableText(youth.first, name: "First name") { value in edit(youth) { $0.first = value } }
                }
                TableColumn("Type", value: \Scout.unitType) { youth in
                    EditableChoice(youth.unitType, choices: RecordChoices.youthUnitTypes, name: "Unit type") { value in
                        edit(youth) { $0.unitType = value }
                    }
                }
                .width(min: 50, ideal: 64, max: 80)
                TableColumn("Unit", value: \Scout.unit) { youth in
                    EditableText(youth.unit, name: "Unit number") { value in edit(youth) { $0.unit = value } }
                }
                .width(min: 40, ideal: 50, max: 70)
            }
            Group {
                TableColumn("Board", value: \Scout.boardTypeText) { youth in
                    EditableChoice(value: youth.boardTypeText, choices: RecordChoices.boardTypes, name: "Board") { value in
                        edit(youth) { $0.boardTypeText = value }
                    } label: {
                        BoardTypeText(youth: youth)
                    }
                }
                .width(min: 50, ideal: 70, max: 90)
                TableColumn("Status", value: \Scout.statusRank) { youth in
                    StatusBadge(statusText: youth.statusText)
                }
                .width(min: 80, ideal: 100, max: 120)
                TableColumn("Room", value: \Scout.room)
                    .width(min: 40, ideal: 50, max: 70)
                TableColumn("Result", value: \Scout.result) { youth in
                    EditableChoice(youth.result, choices: RecordChoices.results, name: "Result") { value in
                        edit(youth) { $0.result = value }
                    }
                }
                .width(min: 70, ideal: 100, max: 130)
                // Who sat changes on the Event page, under the rules for
                // seating; never typed into a table (P-6).
                TableColumn("Chair", value: \Scout.boardChair)
            }
            Group {
                TableColumn("Members", value: \Scout.boardMembers) { youth in
                    Text(youth.boardMembers.withListSeparators).help(youth.boardMembers.withListSeparators)
                }
                TableColumn("Leader", value: \Scout.leader) { youth in
                    EditableText(youth.leader, name: "Leader") { value in edit(youth) { $0.leader = value } }
                }
                TableColumn("Notes", value: \Scout.notes) { youth in
                    EditableText(youth.notes.withCommasRestored, name: "Notes") { value in edit(youth) { $0.notes = value } }
                }
            }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .contextMenu(forSelectionType: Scout.ID.self) { ids in
            if let id = ids.first {
                Button("Show on Event Page") { model.showOnEventPage(id) }
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

    private func edit(_ youth: Scout, _ change: (inout Scout) -> Void) -> Bool {
        model.editYouth(youth.id, change)
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
