import EagleBoardsCore
import SwiftUI

// The pages for the rest of the tables the event keeps, like Results, Adults
// and Youth (SPEC.md P-6). Together they replace the records window. A changed
// cell is saved as it is left and stays off the Undo stack; a deleted record
// is asked about first. The Adult History CSV is read-only.

/// The youth who signed up on SignUpGenius for this event, before any of them
/// has signed in at the door. A youth's birthdate and phone number are never
/// shown here (D-7, D-8).
struct PreRegisteredPage: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var selection: Scout.ID?
    @State private var sortOrder = [KeyPathComparator(\Scout.last)]

    var body: some View {
        let rows = night.scheduledScouts
            .filter { matches(model.searchText, $0.fullName, $0.email, $0.unitName, $0.leader) }
            .sorted(using: sortOrder)

        Table(of: Scout.self, selection: $selection, sortOrder: $sortOrder) {
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
            TableColumn("Board", value: \Scout.boardTypeText) { youth in
                EditableChoice(value: youth.boardTypeText, choices: RecordChoices.boardTypes, name: "Board") { value in
                    edit(youth) { $0.boardTypeText = value }
                } label: {
                    BoardTypeText(youth: youth)
                }
            }
            .width(min: 50, ideal: 70, max: 90)
            TableColumn("Leader", value: \Scout.leader) { youth in
                EditableText(youth.leader, name: "Leader") { value in edit(youth) { $0.leader = value } }
            }
            TableColumn("Email", value: \Scout.email) { youth in
                EditableText(youth.email, name: "Email") { value in edit(youth) { $0.email = value } }
            }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .contextMenu(forSelectionType: Scout.ID.self) { ids in
            if let id = ids.first {
                Button("Delete Pre-Registration…", role: .destructive) { model.confirmDeleteYouth(id, scheduled: true) }
            }
        }
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView("No Pre-Registrations", systemImage: "calendar",
                                           description: Text("File › Import Sign-Ups from SignUpGenius brings in the youth who signed up for today."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }

    private func edit(_ youth: Scout, _ change: (inout Scout) -> Void) -> Bool {
        model.editYouth(youth.id, scheduled: true, change)
    }
}

/// Every adult who has ever signed in, across events: the adult history the
/// sign-in form fills itself in from, read-only (SPEC.md P-6), and searched by
/// name, email or unit. A sign-in writes it, and a change on the Adults page
/// reaches the same adult here. Last Event has a check for those signed in
/// today; double-click someone, or choose Sign In for Today, to put them on
/// tonight's list without the tablet.
struct AdultHistoryPage: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var selection: Set<String> = []

    /// An adult in the history, and whether they have signed in today.
    struct Row: Identifiable, Equatable {
        let adult: Adult
        let signedIn: Bool
        var id: String { adult.id }
    }

    var body: some View {
        let signedIn = Set(night.adults.map(\.id))
        let rows = night.adultHistory
            .filter { matches(model.searchText, $0.fullName, $0.email, $0.unitName) }
            .map { Row(adult: $0, signedIn: signedIn.contains($0.id)) }
        // AppKit, not a SwiftUI Table: see PlainTable.
        PlainTable(
            rows: rows,
            columns: [
                PlainColumn(id: "lastEvent", title: "Last Event", width: 110, style: .digits, ascendingFirst: false,
                            text: { $0.adult.lastEvent }, checked: \.signedIn),
                PlainColumn(id: "last", title: "Last", width: 130, text: { $0.adult.last }),
                PlainColumn(id: "first", title: "First", width: 130, text: { $0.adult.first }),
                PlainColumn(id: "unit", title: "Unit", width: 90, text: { $0.adult.unitDisplay }),
                PlainColumn(id: "final", title: "Final", width: 70, style: .role, text: { $0.adult.finalBoardRoleText }),
                PlainColumn(id: "project", title: "Project", width: 70, style: .role, text: { $0.adult.projectReviewRoleText }),
                PlainColumn(id: "events", title: "Events", width: 55, style: .digits, text: { "\($0.adult.eventCount)" },
                            toolTip: { $0.adult.boardHistory }, sortKey: { $0.adult.eventCount }),
                PlainColumn(id: "email", title: "Email", width: 220, text: { $0.adult.email }),
                PlainColumn(id: "phone", title: "Phone", width: 120, text: { $0.adult.phone }),
            ],
            sortedBy: "last",
            name: "Adult History CSV",
            selection: $selection,
            doubleClick: { id in
                if !signedIn.contains(id) { model.signInFromHistory([id]) }
            },
            menuItems: [
                PlainMenuItem(title: "Sign In for Today",
                              isEnabled: { !$0.isSubset(of: signedIn) },
                              action: { model.signInFromHistory($0.subtracting(signedIn)) }),
            ]
        )
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView("No Adults Yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Every adult who signs in is kept here, across events."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }
}

/// Every project proposal approved at an earlier event (SPEC.md D-22), for a
/// youth who comes to their board of review without the signed page: who,
/// their unit, when, and by whom. Read from every dated folder before this
/// event each time the page is shown, and read only; a mistake is corrected
/// in the earlier event itself. The search looks through names and units.
struct ApprovedProposalsPage: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var found: ApprovedProposals?
    @State private var selection: Set<String> = []

    var body: some View {
        let approvals = (found?.approvals ?? [])
            .filter { matches(model.searchText, "\($0.first) \($0.last)", $0.unit) }
        VStack(alignment: .leading, spacing: 0) {
            if let found {
                VStack(alignment: .leading, spacing: 4) {
                    Text(found.summary)
                    ForEach(found.unreadable, id: \.self) { problem in
                        Label("Could not read \(problem)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            PlainTable(
                rows: approvals,
                columns: [
                    PlainColumn(id: "last", title: "Last", width: 130, text: \.last),
                    PlainColumn(id: "first", title: "First", width: 120, text: \.first),
                    PlainColumn(id: "unit", title: "Unit", width: 100, text: \.unit),
                    PlainColumn(id: "event", title: "Approved", width: 100, style: .digits, ascendingFirst: false, text: \.event),
                    PlainColumn(id: "chair", title: "Chair", width: 150, text: \.chair),
                    PlainColumn(id: "members", title: "Other Members", width: 240, text: { $0.otherMembers.joined(separator: ", ") }),
                    PlainColumn(id: "notes", title: "Notes", width: 260, text: \.notes, toolTip: { $0.notes.isEmpty ? nil : $0.notes }),
                ],
                sortedBy: "last",
                name: "Approved Proposals",
                selection: $selection
            )
            .overlay {
                if found != nil && approvals.isEmpty {
                    if model.searchText.isEmpty {
                        ContentUnavailableView("No Approved Proposals", systemImage: "checkmark.seal",
                                               description: Text("None of the earlier events in this data folder approved a project proposal."))
                    } else {
                        ContentUnavailableView.search(text: model.searchText)
                    }
                }
            }
        }
        // Read each time the page is shown: an earlier event does not change
        // during this one, so nothing polls (D-15).
        .task(id: night.night) { found = night.approvedProposals() }
    }
}

/// The rooms table: what each room is used for today, and whose board is in
/// it. The board type is changed in place; the name, and who is in the room,
/// change from the Event page's room cards (Room › Rename…, Move Board…).
struct RoomsPage: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var sortOrder = [KeyPathComparator(\Room.name)]

    var body: some View {
        @Bindable var model = model
        let rows = night.rooms
            .filter { matches(model.searchText, $0.name, $0.scoutName, $0.leaderNames) }
            .sorted(using: sortOrder)

        Table(of: Room.self, selection: $model.selectedRoomID, sortOrder: $sortOrder) {
            TableColumn("Room", value: \Room.name)
                .width(min: 50, ideal: 70, max: 100)
            TableColumn("Used For", value: \Room.boardTypeText) { room in
                EditableChoice(room.boardTypeText, choices: RecordChoices.boardTypes, name: "Used for") { value in
                    guard let boardType = BoardType(rawValue: value) else { return false }
                    return model.editRoomType(room.id, to: boardType)
                }
            }
            .width(min: 110, ideal: 130, max: 160)
            TableColumn("Youth", value: \Room.scoutName)
            TableColumn("Members", value: \Room.leaderNames) { room in
                Text(room.leaderNames.withListSeparators).help(room.leaderNames.withListSeparators)
            }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .contextMenu(forSelectionType: Room.ID.self) { ids in
            if let id = ids.first, let room = night.room(id: id) {
                Button("Remove Room") {
                    model.selectedRoomID = id
                    model.removeSelectedRoom()
                }
                .disabled(!room.isFree)
            } else {
                Button("Add Room…") { model.sheet = .addRoom }
            }
        } primaryAction: { ids in
            if ids.isEmpty { model.sheet = .addRoom }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ListFooter("Add Room", help: "Add a room for today") { model.sheet = .addRoom }
        }
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView("No Rooms Yet", systemImage: "door.left.hand.closed",
                                           description: Text("Add Room, at the foot of this list, adds one."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }
}

private func matches(_ search: String, _ values: String...) -> Bool {
    let query = search.trimmingCharacters(in: .whitespaces)
    return query.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(query) }
}
