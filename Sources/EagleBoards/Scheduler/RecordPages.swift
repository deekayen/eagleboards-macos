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
    @State private var selection: Set<Adult.ID> = []
    @State private var sortOrder = [KeyPathComparator(\Adult.last)]

    var body: some View {
        let rows = night.adultHistory
            .filter { matches(model.searchText, $0.fullName, $0.email, $0.unitName) }
            .sorted(using: sortOrder)
        let signedIn = Set(night.adults.map(\.id))

        Table(of: Adult.self, selection: $selection, sortOrder: $sortOrder) {
            Group {
                TableColumn("Last Event", value: \Adult.lastEvent) { adult in
                    HStack(spacing: 4) {
                        Text(adult.lastEvent).monospacedDigit()
                        if signedIn.contains(adult.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .help("Signed in today")
                                .accessibilityLabel("Signed in today")
                        }
                    }
                }
                .width(min: 90, ideal: 110, max: 130)
                TableColumn("Last", value: \Adult.last)
                TableColumn("First", value: \Adult.first)
                TableColumn("Unit", value: \Adult.unitName) { adult in
                    Text(adult.unitDisplay)
                }
                .width(min: 60, ideal: 90, max: 130)
                TableColumn("Final", value: \Adult.finalBoardRoleText) { adult in
                    RoleText(role: adult.finalBoardRoleText)
                }
                .width(min: 50, ideal: 70, max: 90)
            }
            Group {
                TableColumn("Project", value: \Adult.projectReviewRoleText) { adult in
                    RoleText(role: adult.projectReviewRoleText)
                }
                .width(min: 50, ideal: 70, max: 90)
                TableColumn("Events", value: \Adult.boardHistory) { adult in
                    Text("\(adult.boardHistory.filter { $0 == "(" }.count)")
                        .monospacedDigit()
                        .help(adult.boardHistory)
                }
                .width(min: 44, ideal: 50, max: 70)
                TableColumn("Email", value: \Adult.email)
                TableColumn("Phone", value: \Adult.phone)
            }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .contextMenu(forSelectionType: Adult.ID.self) { ids in
            if !ids.isEmpty {
                Button("Sign In for Today") { model.signInFromHistory(ids) }
                    .disabled(ids.isSubset(of: signedIn))
            }
        } primaryAction: { ids in
            model.signInFromHistory(ids.subtracting(signedIn))
        }
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

private extension Adult {
    /// The last event they signed in at, from `(2026-08-25)(2026-09-22)`.
    var lastEvent: String {
        boardHistory.split(separator: ")").last.map { $0.trimmingCharacters(in: ["("]) } ?? ""
    }
}

private func matches(_ search: String, _ values: String...) -> Bool {
    let query = search.trimmingCharacters(in: .whitespaces)
    return query.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(query) }
}
