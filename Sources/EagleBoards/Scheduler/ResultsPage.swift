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
    let event: BoardEvent
    let focus: FocusState<SchedulerFocus?>.Binding

    /// The sortable columns, as headed below, for View › Sort By.
    static let order = TableOrder<Scout>([
        .init("Sign-In Number", \.queueOrder), .init("Last Name", \.last), .init("First Name", \.first),
        .init("Unit Type", \.unitType), .init("Unit", \.unit), .init("Board Type", \.boardTypeText),
        .init("Status", \.statusRank), .init("Room", \.room), .init("Result", \.result),
        .init("Chair", \.boardChair), .init("Members", \.boardMembers), .init("Leader", \.leader),
        .init("Notes", \.notes),
    ])

    var body: some View {
        // The same rule Board › Show on Event Page asks (`SchedulerPage`): a
        // youth still waiting has no board here yet.
        let boards = event.scouts.filter { SchedulerPage.results.listsYouth(with: $0.status) }
        let sortOrder = model.sortOrder(for: .results, Self.order)
        let rows = boards
            .filter { matches(model.searchText, $0) }
            .sorted(using: sortOrder.wrappedValue)
        let selection = Binding(get: { model.selectedYouthID }, set: { model.selectYouth($0) })

        Table(of: Scout.self, selection: selection, sortOrder: sortOrder) {
            Group {
                TableColumn("Sign-In Number", value: \Scout.queueOrder) { youth in
                    Text(youth.regNum).help(youth.regNumHelp)
                }
                .width(min: 90, ideal: 104, max: 130)
                TableColumn("Last Name", value: \Scout.last) { youth in
                    EditableText(youth.last.shownValue, name: "Last name") { value in edit(youth) { $0.last = value } }
                }
                TableColumn("First Name", value: \Scout.first) { youth in
                    EditableText(youth.first.shownValue, name: "First name") { value in edit(youth) { $0.first = value } }
                }
                TableColumn("Unit Type", value: \Scout.unitType) { youth in
                    EditableChoice(youth.unitType, choices: RecordChoices.youthUnitTypes, name: "Unit type") { value in
                        edit(youth) { $0.unitType = value }
                    }
                }
                .width(min: 60, ideal: 76, max: 100)
                TableColumn("Unit", value: \Scout.unit) { youth in
                    EditableText(youth.unit, name: "Unit number") { value in edit(youth) { $0.unit = value } }
                }
                .width(min: 40, ideal: 50, max: 70)
            }
            Group {
                TableColumn("Board Type", value: \Scout.boardTypeText) { youth in
                    EditableChoice(value: youth.boardTypeText, choices: RecordChoices.boardTypes, name: "Board type") { value in
                        edit(youth) { $0.boardTypeText = value }
                    } label: {
                        BoardTypeText(youth: youth)
                    }
                }
                .width(min: 110, ideal: 130, max: 160)
                TableColumn("Status", value: \Scout.statusRank) { youth in
                    StatusBadge(statusText: youth.statusText)
                }
                .width(min: 80, ideal: 100, max: 120)
                // Widens far enough for a room named Fellowship Hall, and
                // shows the whole name on hover where it is still cut off.
                TableColumn("Room", value: \Scout.room) { youth in
                    CellText(youth.room).help(youth.room)
                }
                .width(min: 40, ideal: 50, max: 200)
                TableColumn("Result", value: \Scout.result) { youth in
                    EditableChoice(youth.result, choices: RecordChoices.results, name: "Result") { value in
                        edit(youth) { $0.result = value }
                    }
                }
                .width(min: 70, ideal: 100, max: 130)
                // Who sat changes on the Event page, under the rules for
                // seating; never typed into a table (P-6).
                TableColumn("Chair", value: \Scout.boardChair) { youth in
                    CellText(youth.boardChair.shownValue)
                }
            }
            Group {
                TableColumn("Members", value: \Scout.boardMembers) { youth in
                    let members = youth.boardMemberNames(among: event.adults).joined(separator: ", ")
                    CellText(members).help(members)
                }
                TableColumn("Leader", value: \Scout.leader) { youth in
                    EditableText(youth.leader.shownValue, name: "Leader") { value in edit(youth) { $0.leader = value } }
                }
                TableColumn("Notes", value: \Scout.notes) { youth in
                    EditableText(youth.notes.shownMultilineValue, name: "Notes") { value in edit(youth) { $0.notes = value } }
                }
            }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .focused(focus, equals: .table(.results))
        // Return in the search: the first board found, with the focus.
        .onChange(of: model.searchSubmitted) {
            guard let first = rows.first else { return }
            model.selectYouth(first.id)
            focus.wrappedValue = .table(.results)
        }
        .accessibilityLabel(model.page.title)
        .speaksSearchCount(model.searchText, shown: rows.count, total: boards.count)
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
        return [youth.shownFullName, youth.unitName, youth.unitLabel, youth.unitDisplay, youth.leader.shownValue, youth.room, youth.regNum,
                youth.boardChair.shownValue, youth.boardMembers.shownValue, result, youth.notes.shownValue]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
