import EagleBoardsCore
import SwiftUI

/// The youth table (SPEC.md P-6): every youth who signed in at this event, in
/// sign-in order, edited in place. A changed cell is saved as it is left and
/// stays off the Undo stack. The status and the room are read-only: they
/// change only through the Event page's steps, which take and free a room
/// and its members. Double-click a youth to see them on the Event page.
///
/// A youth's birthdate and phone number are never shown here (D-7, D-8).
struct YouthPage: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent
    @State private var sortOrder = [KeyPathComparator(\Scout.queueOrder)]

    var body: some View {
        let rows = event.scouts
            .filter { matches(model.searchText, $0) }
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
                TableColumn("Leader", value: \Scout.leader) { youth in
                    EditableText(youth.leader, name: "Leader") { value in edit(youth) { $0.leader = value } }
                }
                TableColumn("Email", value: \Scout.email) { youth in
                    EditableText(youth.email, name: "Email") { value in edit(youth) { $0.email = value } }
                }
                TableColumn("Board", value: \Scout.boardTypeText) { youth in
                    EditableChoice(value: youth.boardTypeText, choices: RecordChoices.boardTypes, name: "Board") { value in
                        edit(youth) { $0.boardTypeText = value }
                    } label: {
                        BoardTypeText(youth: youth)
                    }
                }
                .width(min: 50, ideal: 70, max: 90)
                TableColumn("Room", value: \Scout.room)
                    .width(min: 40, ideal: 50, max: 70)
                TableColumn("Status", value: \Scout.statusRank) { youth in
                    StatusBadge(statusText: youth.statusText)
                }
                .width(min: 80, ideal: 100, max: 120)
            }
            TableColumn("Result", value: \Scout.result) { youth in
                EditableChoice(youth.result, choices: RecordChoices.results, name: "Result") { value in
                    edit(youth) { $0.result = value }
                }
            }
            .width(min: 70, ideal: 100, max: 130)
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .contextMenu(forSelectionType: Scout.ID.self) { ids in
            if let id = ids.first {
                Button("Show on Event Page") { model.showOnEventPage(id) }
                Divider()
                Button("Delete Youth…", role: .destructive) { model.confirmDeleteYouth(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                model.showOnEventPage(id)
            }
        }
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView("No Youth Yet", systemImage: "person.crop.circle.badge.clock",
                                           description: Text("Youth appear here the moment they sign in at the tablet."))
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
        return [youth.fullName, youth.unitName, youth.unitLabel, youth.leader, youth.room, youth.regNum, youth.email]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
