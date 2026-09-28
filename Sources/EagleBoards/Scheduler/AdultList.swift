import EagleBoardsCore
import SwiftUI

/// Every adult who has signed in tonight, the People page (SPEC.md P-6).
/// Select several with Command or Shift and add them to the board being drawn
/// up, or drag them onto it in the inspector. Their details are edited in
/// place, and it is here that someone is promoted to Chair; a changed cell is
/// saved as it is left and stays off the Undo stack. Their room is read-only:
/// it changes only through the Event page's steps. It replaces the records
/// window's list of tonight's adults.
/// Add Adult, at the foot of the list, in the Adult menu, or by
/// double-clicking below the last row, signs in someone who would rather not
/// use the tablet.
struct AdultList: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var sortOrder = [KeyPathComparator(\Adult.last)]

    var body: some View {
        @Bindable var model = model
        let draft = model.draft
        let rows = night.adults
            .filter { matches(model.searchText, $0) }
            .sorted(using: sortOrder)

        Table(of: Adult.self, selection: $model.selectedAdultIDs, sortOrder: $sortOrder) {
            Group {
                TableColumn("Status", value: \Adult.room) { adult in
                    AdultStatusLabel(adult: adult, isOnDraft: draft?.memberIDs.contains(adult.id) == true)
                }
                .width(min: 80, ideal: 110, max: 150)
                TableColumn("Last", value: \Adult.last) { adult in
                    EditableText(adult.last, name: "Last name") { value in edit(adult) { $0.last = value } }
                }
                TableColumn("First", value: \Adult.first) { adult in
                    EditableText(adult.first, name: "First name") { value in edit(adult) { $0.first = value } }
                }
                TableColumn("Type", value: \Adult.unitType) { adult in
                    EditableChoice(adult.unitType, choices: RecordChoices.adultUnitTypes, name: "Unit type") { value in
                        edit(adult) { $0.unitType = value }
                    }
                }
                .width(min: 50, ideal: 70, max: 90)
                TableColumn("Unit", value: \Adult.unit) { adult in
                    EditableText(adult.unit, name: "Unit number") { value in edit(adult) { $0.unit = value } }
                }
                .width(min: 40, ideal: 50, max: 70)
            }
            Group {
                TableColumn("Final", value: \Adult.finalBoardRoleText) { adult in
                    RoleChoice(role: adult.finalBoardRoleText, name: "Final Board role") { value in
                        edit(adult) { $0.finalBoardRoleText = value }
                    }
                }
                .width(min: 60, ideal: 80, max: 100)
                TableColumn("Project", value: \Adult.projectReviewRoleText) { adult in
                    RoleChoice(role: adult.projectReviewRoleText, name: "Proposal Review role") { value in
                        edit(adult) { $0.projectReviewRoleText = value }
                    }
                }
                .width(min: 60, ideal: 80, max: 100)
                // Volunteering toward a Wood Badge ticket item.
                TableColumn("WB", value: \Adult.woodBadge) { adult in
                    WoodBadgeChoice(value: adult.woodBadge) { value in edit(adult) { $0.woodBadge = value } }
                }
                .width(min: 40, ideal: 48, max: 60)
                TableColumn("With", value: \Adult.supporting) { adult in
                    let names = supportedNames(adult)
                    Text(names).foregroundStyle(.secondary).help(names)
                }
            }
            Group {
                TableColumn("Email", value: \Adult.email) { adult in
                    EditableText(adult.email, name: "Email") { value in edit(adult) { $0.email = value } }
                }
                TableColumn("Phone", value: \Adult.phone) { adult in
                    EditableText(adult.phone, name: "Phone") { value in edit(adult) { $0.phone = value } }
                }
            }
        } rows: {
            ForEach(rows) { adult in
                TableRow(adult).draggable(DragPayload.adult(adult.id))
            }
        }
        .contextMenu(forSelectionType: Adult.ID.self) { ids in
            if ids.isEmpty {
                Button("Add Adult…") { model.sheet = .addAdult }
            } else {
                AdultActionButtons(model: model, adultIDs: ids)
                if ids.count == 1, let id = ids.first {
                    Divider()
                    Button("Delete Adult…", role: .destructive) { model.confirmDeleteAdult(id) }
                }
            }
        } primaryAction: { ids in
            // Double-clicking below the last row adds someone.
            if ids.isEmpty {
                model.sheet = .addAdult
            } else {
                model.addToDraft(Array(ids))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ListFooter("Add Adult", help: "Sign in an adult who would rather not use the tablet") { model.sheet = .addAdult }
        }
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView("No Adults Yet", systemImage: "person.2",
                                           description: Text("Adults appear here the moment they sign in at the tablet."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }

    private func edit(_ adult: Adult, _ change: (inout Adult) -> Void) -> Bool {
        model.editAdult(adult.id, change)
    }

    private func supportedNames(_ adult: Adult) -> String {
        adult.supporting.split(separator: "|")
            .compactMap { night.scout(id: String($0))?.fullName }
            .joined(separator: ", ")
    }

    private func matches(_ search: String, _ adult: Adult) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [adult.fullName, adult.unitName, adult.unitLabel, adult.room, adult.email]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Free, on a board in a room, or gone home -- in words and a symbol, not
/// only a color.
struct AdultStatusLabel: View {
    let adult: Adult
    var isOnDraft = false

    var body: some View {
        if adult.isDisabledForTonight {
            Label("Gone home", systemImage: "moon.zzz")
                .foregroundStyle(.secondary)
                .help("Disabled for today. Enable brings them back.")
        } else if adult.isOnBoard {
            Label("Room \(adult.room)", systemImage: "person.3.fill")
                .help("On the board in room \(adult.room)")
        } else if isOnDraft {
            Label("This board", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .help("On the board being drawn up for the selected youth")
        } else {
            Label("Free", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

/// What can be done to adults: the Adult menu, and the context menu on their
/// rows. Acting on rows that are not selected selects them first.
struct AdultActionButtons: View {
    let model: AppModel
    /// Nil acts on the selected adults.
    var adultIDs: Set<Adult.ID>?

    var body: some View {
        let youth = model.selectedYouth
        let draft = model.draft
        let ids = adultIDs ?? model.selectedAdultIDs
        let adults = model.night?.adults.filter { ids.contains($0.id) } ?? []
        let single = adults.count == 1 ? adults.first : nil

        Button(youth.map { "Add to \($0.first)'s Board" } ?? "Add to Board") {
            run { model.addToDraft(Array(ids)) }
        }
        .keyboardShortcut("b")
        .disabled(draft == nil || !ids.contains { draft?.memberIDs.contains($0) == false })
        Button("Remove from Board") { run { model.removeFromDraft(ids) } }
            .disabled(draft == nil || !ids.contains { draft?.memberIDs.contains($0) == true })
        Divider()
        if let single, let youth, single.supports(youth.id) {
            Button("Unlink from \(youth.fullName)") { run { model.toggleSupportLink() } }
        } else {
            Button(youth.map { "Came to Support \($0.fullName)" } ?? "Came to Support the Selected Youth") {
                run { model.toggleSupportLink() }
            }
            .disabled(single == nil || youth == nil)
        }
        Divider()
        Button("Enable for Today") { run { model.setAvailable(true) } }
            .disabled(!adults.contains(where: \.isDisabledForTonight))
        Button("Disable for Today") { run { model.setAvailable(false) } }
            .disabled(!adults.contains(where: \.isAvailable))
    }

    private func run(_ action: () -> Void) {
        if let adultIDs, !adultIDs.isEmpty, !adultIDs.isSubset(of: model.selectedAdultIDs) {
            model.selectedAdultIDs = adultIDs
        }
        action()
    }
}

/// Sign an adult in by hand, for someone who would rather not use the tablet.
/// It is the tablet's own sign-in (`Adult.handSignInForm`). Someone who has
/// served before is found in the adult history and fills the form in; a role
/// left at As Last Time keeps the one in the history.
struct AddAdultSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    /// The history record the form was filled in from.
    @State private var known: Adult?

    @State private var first = ""
    @State private var last = ""
    @State private var unitType: UnitType = .troop
    @State private var unit = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var finalBoard: BoardRole?
    @State private var projectReview: BoardRole?
    @State private var woodBadge = false
    @State private var problem: String?

    var body: some View {
        SheetLayout(
            title: "Add an Adult",
            message: "For an adult who would rather not sign in at the tablet. They are signed in for today as if they had."
        ) {
            Section {
                if let known {
                    LabeledContent("From the adult history") {
                        HStack {
                            Text("\(known.fullName), \(known.unitDisplay)")
                            Button("Start Over") { startOver() }
                                .buttonStyle(.link)
                        }
                    }
                } else {
                    TextField("Signed in before?", text: $search, prompt: Text("Search the adult history by name, email or unit"))
                    ForEach(model.night?.historyMatches(for: search, limit: 5) ?? []) { match in
                        Button {
                            fill(from: match)
                        } label: {
                            HStack {
                                Text(match.fullName)
                                Text(match.unitDisplay).foregroundStyle(.secondary)
                                Spacer()
                                Text(match.email).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Fill in the form from \(match.fullName)'s record")
                    }
                }
            }
            Section {
                TextField("First name", text: $first)
                TextField("Last name", text: $last)
                Picker("Unit type", selection: $unitType) {
                    ForEach(UnitType.allCases) { Text($0.rawValue).tag($0) }
                }
                if unitType.hasUnitNumber {
                    TextField("Unit #", text: $unit)
                }
                TextField("Email", text: $email)
                TextField("Phone", text: $phone)
            }
            Section {
                rolePicker("Final Board", selection: $finalBoard)
                rolePicker("Proposal Review", selection: $projectReview)
                Toggle("Counting today toward a Wood Badge ticket item", isOn: $woodBadge)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("As Last Time uses the role in the adult history, or Member for someone new.")
                        .foregroundStyle(.secondary)
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    }
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add Adult") {
                do {
                    try model.addAdult(Adult.handSignInForm(
                        historyID: known?.id,
                        first: first, last: last, email: email, phone: phone, unitType: unitType.rawValue, unit: unit,
                        finalBoard: finalBoard, projectReview: projectReview, woodBadge: woodBadge
                    ))
                    dismiss()
                } catch {
                    problem = error.localizedDescription
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(first.trimmingCharacters(in: .whitespaces).isEmpty || last.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func fill(from match: Adult) {
        known = match
        first = match.first
        last = match.last
        unitType = UnitType(rawValue: match.unitType) ?? .troop
        unit = match.unit
        email = match.email
        phone = match.phone
        finalBoard = match.role(for: .finalBoard)
        projectReview = match.role(for: .projectReview)
    }

    private func startOver() {
        known = nil
        search = ""
        first = ""
        last = ""
        unitType = .troop
        unit = ""
        email = ""
        phone = ""
        finalBoard = nil
        projectReview = nil
    }

    private func rolePicker(_ title: String, selection: Binding<BoardRole?>) -> some View {
        Picker(title, selection: selection) {
            Text("As Last Time").tag(BoardRole?.none)
            ForEach(BoardRole.allCases) { role in
                Text(role == .unavailable ? "No Thanks" : role.rawValue).tag(Optional(role))
            }
        }
    }
}

/// A board role chosen from a menu, shown as `RoleText`.
struct RoleChoice: View {
    let role: String
    let name: String
    let save: (String) -> Bool

    var body: some View {
        EditableChoice(value: role, choices: RecordChoices.roles, name: name, save: save) {
            RoleText(role: role)
        }
    }
}

/// Whether an adult is counting today toward a Wood Badge ticket item: the
/// Wood Badge mark, and Yes or No while it is being changed (SPEC.md D-20).
struct WoodBadgeChoice: View {
    let value: String
    let save: (String) -> Bool

    var body: some View {
        EditableChoice(value: value, choices: [("", "No"), ("Y", "Yes")], name: "Wood Badge", save: save) {
            if value == "Y" {
                WoodBadgeIcon()
            }
        }
    }
}

/// The bar at the foot of a table page with its Add button, as under a Mac
/// list.
struct ListFooter: View {
    let title: String
    let help: String
    let action: () -> Void

    init(_ title: String, help: String, action: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.action = action
    }

    var body: some View {
        HStack {
            Button(action: action) {
                Label(title, systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .help(help)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// A board role, with Chair made easy to spot.
struct RoleText: View {
    let role: String

    var body: some View {
        switch BoardRole(rawValue: role) {
        case .chair:
            Text("Chair").fontWeight(.semibold).foregroundStyle(.tint)
        case .unavailable:
            Text("—").foregroundStyle(.secondary).help("No thanks")
        default:
            Text(role)
        }
    }
}
