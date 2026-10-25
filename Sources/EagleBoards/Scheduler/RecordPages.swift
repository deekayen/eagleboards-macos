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
    let event: BoardEvent
    let focus: FocusState<SchedulerFocus?>.Binding
    @State private var selection: Scout.ID?

    /// The sortable columns, as headed below, for View › Sort By.
    static let order = TableOrder<Scout>([
        .init("Last Name", \.last), .init("First Name", \.first), .init("Unit Type", \.unitType), .init("Unit", \.unit),
        .init("Board Type", \.boardTypeText), .init("Leader", \.leader), .init("Email", \.email),
    ])

    var body: some View {
        let sortOrder = model.sortOrder(for: .preRegistered, Self.order)
        let rows = event.scheduledScouts
            .filter { matches(model.searchText, $0.shownFullName, $0.email, $0.unitName, $0.unitDisplay, $0.leader.shownValue) }
            .sorted(using: sortOrder.wrappedValue)

        Table(of: Scout.self, selection: $selection, sortOrder: sortOrder) {
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
            TableColumn("Board Type", value: \Scout.boardTypeText) { youth in
                EditableChoice(value: youth.boardTypeText, choices: RecordChoices.boardTypes, name: "Board type") { value in
                    edit(youth) { $0.boardTypeText = value }
                } label: {
                    BoardTypeText(youth: youth)
                }
            }
            .width(min: 110, ideal: 130, max: 160)
            TableColumn("Leader", value: \Scout.leader) { youth in
                EditableText(youth.leader.shownValue, name: "Leader") { value in edit(youth) { $0.leader = value } }
            }
            TableColumn("Email", value: \Scout.email) { youth in
                EditableText(youth.email, name: "Email") { value in edit(youth) { $0.email = value } }
            }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .focused(focus, equals: .table(.preRegistered))
        // Return in the search: the first pre-registration found, with the focus.
        .onChange(of: model.searchSubmitted) {
            guard let first = rows.first else { return }
            selection = first.id
            focus.wrappedValue = .table(.preRegistered)
        }
        .accessibilityLabel(model.page.title)
        .speaksSearchCount(model.searchText, shown: rows.count, total: event.scheduledScouts.count)
        .contextMenu(forSelectionType: Scout.ID.self) { ids in
            if let id = ids.first {
                Button("Delete Pre-Registration…", role: .destructive) { model.confirmDeleteYouth(id, scheduled: true) }
            }
        }
        .onDeleteCommand(perform: selection.map { id in { model.confirmDeleteYouth(id, scheduled: true) } })
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty && model.isImporting {
                    ContentUnavailableView("Importing Sign-Ups…", systemImage: "square.and.arrow.down",
                                           description: Text("The youth who signed up for today appear here once SignUpGenius answers."))
                } else if model.searchText.isEmpty {
                    NoPreRegistrations()
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
/// today; double-click someone, or choose Sign In for Today here or in the
/// Adult menu, to put them on the event's list without the tablet. The
/// selection is the model's, for that menu.
struct AdultHistoryPage: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent

    /// An adult in the history, and whether they have signed in today.
    struct Row: Identifiable, Equatable {
        let adult: Adult
        let signedIn: Bool
        var id: String { adult.id }
    }

    /// The table's columns, which View › Sort By lists too. `today`'s date
    /// shows as Today.
    static func columns(today: String) -> [PlainColumn<Row>] {
        [
            // The date in words, "Today" for today's, sorted by the
            // folder's name, which is the help.
            PlainColumn(id: "lastEvent", title: "Last Event", width: 140, style: .digits, ascendingFirst: false,
                        text: { $0.adult.lastEvent == today ? "Today" : Timestamp.shownDate($0.adult.lastEvent) },
                        toolTip: { $0.adult.lastEvent.isEmpty ? nil : $0.adult.lastEvent }, checked: \.signedIn,
                        sortText: { $0.adult.lastEvent }),
            PlainColumn(id: "last", title: "Last Name", width: 130, text: { $0.adult.last.shownValue }),
            PlainColumn(id: "first", title: "First Name", width: 130, text: { $0.adult.first.shownValue }),
            PlainColumn(id: "unit", title: "Unit", width: 90, text: { $0.adult.unitDisplay }),
            PlainColumn(id: "final", title: "Final Board Role", width: 106, style: .role, text: { $0.adult.finalBoardRoleText }),
            PlainColumn(id: "project", title: "Proposal Review Role", width: 132, style: .role,
                        text: { $0.adult.projectReviewRoleText }),
            PlainColumn(id: "events", title: "Events", width: 55, style: .digits, text: { "\($0.adult.eventCount)" },
                        toolTip: { $0.adult.boardHistory }, sortKey: { $0.adult.eventCount }),
            PlainColumn(id: "email", title: "Email", width: 220, text: { $0.adult.email }),
            PlainColumn(id: "phone", title: "Phone", width: 120, text: { $0.adult.phone }),
        ]
    }

    static var sortColumns: [SortColumn] { columns(today: "").map(\.sortColumn) }

    var body: some View {
        @Bindable var model = model
        let signedIn = Set(event.adults.map(\.id))
        let rows = event.adultHistory
            .filter { matches(model.searchText, $0.shownFullName, $0.email, $0.unitName, $0.unitDisplay) }
            .map { Row(adult: $0, signedIn: signedIn.contains($0.id)) }
        // Read here, so View › Sort By redraws the page.
        let sort = model.sort(for: .adultHistory)
        // AppKit, not a SwiftUI Table: see PlainTable.
        PlainTable(
            rows: rows,
            columns: Self.columns(today: model.today),
            sort: Binding(get: { sort }, set: { model.setSort($0, for: .adultHistory) }),
            name: "Adult History CSV",
            selection: $model.selectedHistoryIDs,
            doubleClick: { id in
                if !signedIn.contains(id) { model.signInFromHistory([id]) }
            },
            menuItems: [
                PlainMenuItem(title: "Sign In for Today",
                              isEnabled: { !$0.isSubset(of: signedIn) },
                              action: { model.signInFromHistory($0.subtracting(signedIn)) }),
            ],
            takesFocus: true,
            firstRowRequest: model.searchSubmitted,
            focusRequest: model.plainTableFocusRequests
        )
        .speaksSearchCount(model.searchText, shown: rows.count, total: event.adultHistory.count)
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
    let event: BoardEvent
    @State private var found: ApprovedProposals?
    @State private var selection: Set<String> = []

    /// The table's columns, which View › Sort By lists too.
    static let columns: [PlainColumn<ApprovedProposal>] = [
        PlainColumn(id: "last", title: "Last Name", width: 130, text: \.last),
        PlainColumn(id: "first", title: "First Name", width: 120, text: \.first),
        PlainColumn(id: "unit", title: "Unit", width: 100, text: \.unit),
        PlainColumn(id: "event", title: "Approved On", width: 140, style: .digits, ascendingFirst: false,
                    text: { Timestamp.shownDate($0.event) }, toolTip: { $0.event }, sortText: \.event),
        PlainColumn(id: "chair", title: "Chair", width: 150, text: \.chair),
        PlainColumn(id: "members", title: "Other Members", width: 240, text: { $0.otherMembers.joined(separator: ", ") }),
        PlainColumn(id: "notes", title: "Notes", width: 260, text: \.notes, toolTip: { $0.notes.isEmpty ? nil : $0.notes }),
    ]

    static var sortColumns: [SortColumn] { columns.map(\.sortColumn) }

    var body: some View {
        let approvals = (found?.approvals ?? [])
            .filter { matches(model.searchText, "\($0.first) \($0.last)", $0.unit) }
        // Read here, so View › Sort By redraws the page.
        let sort = model.sort(for: .approvedProposals)
        VStack(alignment: .leading, spacing: 0) {
            if let found {
                VStack(alignment: .leading, spacing: 4) {
                    Text(found.shownSummary()).help(found.summary)
                    ForEach(found.unreadable, id: \.event) { problem in
                        NoticeLabel.warning(problem.shownLine()).help(problem.event)
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            PlainTable(
                rows: approvals,
                columns: Self.columns,
                sort: Binding(get: { sort }, set: { model.setSort($0, for: .approvedProposals) }),
                name: "Approved Proposals",
                selection: $selection,
                takesFocus: true,
                firstRowRequest: model.searchSubmitted,
                focusRequest: model.plainTableFocusRequests
            )
            .speaksSearchCount(model.searchText, shown: approvals.count, total: found?.approvals.count ?? 0)
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
        .task(id: event.date) { found = event.approvedProposals() }
    }
}

/// The rooms table: what each room is used for today, and whose board is in
/// it. The board type is changed in place; the name, and who is in the room,
/// change from the Event page's room cards (Room › Rename…, Move Board…).
/// Double-click a room, or choose Show on Event Page, to see its card.
struct RoomsPage: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent
    let focus: FocusState<SchedulerFocus?>.Binding

    /// The sortable columns, as headed below, for View › Sort By.
    static let order = TableOrder<Room>([
        .init("Room", \.name), .init("Used For", \.boardTypeText), .init("Youth", \.scoutName), .init("Members", \.leaderNames),
    ])

    var body: some View {
        @Bindable var model = model
        let sortOrder = model.sortOrder(for: .rooms, Self.order)
        let rows = event.rooms
            .filter { matches(model.searchText, $0.name, $0.scoutName.shownValue, $0.leaderNames.shownValue) }
            .sorted(using: sortOrder.wrappedValue)

        Table(of: Room.self, selection: $model.selectedRoomID, sortOrder: sortOrder) {
            TableColumn("Room", value: \Room.name) { room in
                Text(room.name).help(room.name)
            }
            .width(min: 50, ideal: 70, max: 200)
            TableColumn("Used For", value: \Room.boardTypeText) { room in
                EditableChoice(room.boardTypeText, choices: RecordChoices.boardTypes, name: "Used for") { value in
                    guard let boardType = BoardType(rawValue: value) else { return false }
                    return model.editRoomType(room.id, to: boardType)
                }
            }
            .width(min: 110, ideal: 130, max: 160)
            // Empty for a free room: an old file's "-" is neither shown nor read.
            TableColumn("Youth", value: \Room.scoutName) { room in
                CellText(room.isFree ? "" : room.scoutName.shownValue)
            }
            TableColumn("Members", value: \Room.leaderNames) { room in
                let members = event.memberNames(in: room).joined(separator: ", ")
                CellText(members).help(members)
            }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .focused(focus, equals: .table(.rooms))
        // Return in the search: the first room found, with the focus.
        .onChange(of: model.searchSubmitted) {
            guard let first = rows.first else { return }
            model.selectedRoomID = first.id
            focus.wrappedValue = .table(.rooms)
        }
        .accessibilityLabel(model.page.title)
        .speaksSearchCount(model.searchText, shown: rows.count, total: event.rooms.count)
        .contextMenu(forSelectionType: Room.ID.self) { ids in
            // A context menu lists only what applies: a room in use cannot
            // be removed.
            if let id = ids.first, let room = event.room(id: id) {
                Button("Show on Event Page") { model.showRoomOnEventPage(id) }
                if room.isFree {
                    Divider()
                    Button("Remove Room…") {
                        model.selectedRoomID = id
                        model.removeSelectedRoom()
                    }
                }
            } else {
                Button("Add Room…") { model.present(.addRoom) }
            }
        } primaryAction: { ids in
            // As on Results and Youth, double-clicking a row shows it on the
            // Event page; below the last row it adds a room.
            if let id = ids.first {
                model.showRoomOnEventPage(id)
            } else {
                model.present(.addRoom)
            }
        }
        // Room › Remove Room…, which a room in use dims, as it does Edit › Delete.
        .onDeleteCommand(perform: model.selectedRoom?.isFree == true ? { model.removeSelectedRoom() } : nil)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ListFooter("Add Room…", help: "Add a room for today") { model.present(.addRoom) }
        }
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    NoRoomsYet(event: event)
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }
}

/// The Pre-Registered page before any sign-ups are in, offering the import,
/// or Settings when no SignUpGenius key is saved yet.
private struct NoPreRegistrations: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.hasSignUpGeniusKey {
            ContentUnavailableView {
                Label("No Pre-Registrations", systemImage: "calendar")
            } description: {
                Text("Import the youth who signed up on SignUpGenius for today.")
            } actions: {
                Button("Import Sign-Ups") { Task { await model.importSignUps() } }
            }
        } else {
            ContentUnavailableView {
                Label("No Pre-Registrations", systemImage: "calendar")
            } description: {
                Text("Save a SignUpGenius key in Settings to import the youth who signed up for today.")
            } actions: {
                SettingsLink { Text("Open Settings…") }
            }
        }
    }
}

private func matches(_ search: String, _ values: String...) -> Bool {
    let query = search.trimmingCharacters(in: .whitespaces)
    return query.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(query) }
}
