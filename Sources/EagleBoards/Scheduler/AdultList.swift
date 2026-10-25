import EagleBoardsCore
import SwiftUI

/// Every adult who has signed in at this event, the Adults page (SPEC.md P-6).
/// Select several with Command or Shift and add them to the board being drawn
/// up, or drag them onto it in the inspector. Their details are edited in
/// place, and it is here that someone is promoted to Chair; a changed cell is
/// saved as it is left and stays off the Undo stack, and a change to their
/// name, unit, contact or roles reaches the adult history too. Their room is
/// read-only: it changes only through the Event page's steps.
/// Add Adult…, at the foot of the list, in the Adult menu, or by
/// double-clicking below the last row, signs in someone who would rather not
/// use the tablet.
struct AdultList: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent
    @State private var sortOrder = [KeyPathComparator(\Adult.last)]

    var body: some View {
        @Bindable var model = model
        let draft = model.draft
        let rows = event.adults
            .filter { matches(model.searchText, $0) }
            .sorted(using: sortOrder)

        Table(of: Adult.self, selection: $model.selectedAdultIDs, sortOrder: $sortOrder) {
            Group {
                TableColumn("Status", value: \Adult.room) { adult in
                    AdultStatusLabel(adult: adult, isOnDraft: draft?.memberIDs.contains(adult.id) == true)
                }
                .width(min: 80, ideal: 110, max: 150)
                TableColumn("Last Name", value: \Adult.last) { adult in
                    EditableText(adult.last.shownValue, name: "Last name") { value in edit(adult) { $0.last = value } }
                }
                TableColumn("First Name", value: \Adult.first) { adult in
                    EditableText(adult.first.shownValue, name: "First name") { value in edit(adult) { $0.first = value } }
                }
                TableColumn("Unit Type", value: \Adult.unitType) { adult in
                    EditableChoice(adult.unitType, choices: RecordChoices.adultUnitTypes, name: "Unit type") { value in
                        edit(adult) { $0.unitType = value }
                    }
                }
                .width(min: 60, ideal: 80, max: 110)
                TableColumn("Unit", value: \Adult.unit) { adult in
                    EditableText(adult.unit, name: "Unit number") { value in edit(adult) { $0.unit = value } }
                }
                .width(min: 40, ideal: 50, max: 70)
            }
            Group {
                TableColumn("Final Board Role", value: \Adult.finalBoardRoleText) { adult in
                    RoleChoice(role: adult.finalBoardRoleText, name: "Final Board role") { value in
                        edit(adult) { $0.finalBoardRoleText = value }
                    }
                }
                .width(min: 92, ideal: 106, max: 140)
                TableColumn("Proposal Review Role", value: \Adult.projectReviewRoleText) { adult in
                    RoleChoice(role: adult.projectReviewRoleText, name: "Proposal Review role") { value in
                        edit(adult) { $0.projectReviewRoleText = value }
                    }
                }
                .width(min: 120, ideal: 132, max: 160)
                // Volunteering toward a Wood Badge ticket item.
                TableColumn("Wood Badge", value: \Adult.woodBadge) { adult in
                    WoodBadgeChoice(value: adult.woodBadge) { value in edit(adult) { $0.woodBadge = value } }
                }
                .width(min: 74, ideal: 88, max: 110)
                // Whom they introduce to their board of review (SPEC.md D-23).
                TableColumn("Introduces", value: \Adult.supporting) { adult in
                    let names = supportedNames(adult)
                    CellText(names).foregroundStyle(.secondary).help(names)
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
        .accessibilityLabel(model.page.title)
        .speaksSearchCount(model.searchText, shown: rows.count, total: event.adults.count)
        .contextMenu(forSelectionType: Adult.ID.self) { ids in
            if ids.isEmpty {
                Button("Add Adult…") { model.present(.addAdult) }
            } else {
                AdultActionButtons(model: model, adultIDs: ids, inContextMenu: true)
            }
        } primaryAction: { ids in
            // Double-clicking below the last row adds someone.
            if ids.isEmpty {
                model.present(.addAdult)
            } else {
                model.addToDraft(Array(ids))
            }
        }
        // One adult at a time, as in the context menu, asking first.
        .onDeleteCommand(perform: model.singleSelectedAdult.map { adult in { model.confirmDeleteAdult(adult.id) } })
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ListFooter("Add Adult…", help: "Sign in an adult who would rather not use the tablet") { model.present(.addAdult) }
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
            .compactMap { event.scout(id: String($0))?.shownFullName }
            .joined(separator: ", ")
    }

    private func matches(_ search: String, _ adult: Adult) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [adult.shownFullName, adult.unitName, adult.unitLabel, adult.unitDisplay, adult.room, adult.email]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Free, on a board in a room, or gone home: in words and a symbol, not
/// only a color.
struct AdultStatusLabel: View {
    let adult: Adult
    var isOnDraft = false

    var body: some View {
        if adult.isDisabledForToday {
            Label("Gone home", systemImage: "moon.zzz")
                .foregroundStyle(.secondary)
                .help("Disabled for today. Enable brings them back.")
        } else if adult.isOnBoard {
            Label("Room \(adult.room)", systemImage: "person.3.fill")
                .help("On the board in room \(adult.room)")
        } else if isOnDraft {
            // The tint on the symbol only: accent-colored words fall short of
            // the contrast text needs.
            Label {
                Text("This board")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
            .help("On the board being drawn up for the selected youth")
        } else {
            Label("Free", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

/// What can be done to adults: the Adult menu, and the context menu on their
/// rows. Acting on rows that are not selected selects them first.
///
/// The context menu lists only what applies, in three groups: the selected
/// youth's board and whether this adult introduces them; Enable or Disable
/// for Today; and, for one adult, Delete Adult….
struct AdultActionButtons: View {
    let model: AppModel
    /// Nil acts on the selected adults.
    var adultIDs: Set<Adult.ID>?
    var inContextMenu = false

    var body: some View {
        let youth = model.selectedYouth
        let draft = model.draft
        let ids = adultIDs ?? model.selectedAdultIDs
        let adults = model.event?.adults.filter { ids.contains($0.id) } ?? []
        let single = adults.count == 1 ? adults.first : nil
        let canAdd = draft.map { draft in ids.contains { !draft.memberIDs.contains($0) } } ?? false
        let canRemove = draft.map { draft in ids.contains { draft.memberIDs.contains($0) } } ?? false
        let canMakeChair = single.map { model.canMakeChair($0) } ?? false
        let canLink = single != nil && youth != nil
        let canEnable = adults.contains(where: \.isDisabledForToday)
        let canDisable = adults.contains(where: \.isAvailable)
        let forYouth = canAdd || canRemove || canMakeChair || canLink

        command(youth.map { "Add to \($0.first.shownValue)'s Board" } ?? "Add to Board", applies: canAdd,
                shortcut: KeyboardShortcut("b")) {
            model.addToDraft(Array(ids))
        }
        command("Remove from Board", applies: canRemove) { model.removeFromDraft(ids) }
        command("Make Chair", applies: canMakeChair) { if let single { model.makeChair(single.id) } }
        if !inContextMenu {
            Divider()
        }
        // One checked item for the D-23 link, whichever way it goes.
        if canLink || !inContextMenu {
            Toggle(youth.map { "Introduces \($0.shownFullName)" } ?? "Introduces Selected Youth", isOn: Binding(
                get: { youth.map { single?.supports($0.id) == true } ?? false },
                set: { _ in run { model.toggleSupportLink() } }
            ))
            .disabled(!canLink)
        }
        if !inContextMenu || (forYouth && (canEnable || canDisable)) {
            Divider()
        }
        command("Enable for Today", applies: canEnable) { model.setAvailable(true) }
        command("Disable for Today", applies: canDisable) { model.setAvailable(false) }
        if inContextMenu, let single {
            if forYouth || canEnable || canDisable {
                Divider()
            }
            Button("Delete Adult…", role: .destructive) { model.confirmDeleteAdult(single.id) }
        }
    }

    private func command(
        _ title: String, applies: Bool, shortcut: KeyboardShortcut? = nil, _ action: @escaping @MainActor () -> Void
    ) -> MenuCommand {
        MenuCommand(title, applies: applies, shortcut: shortcut, inContextMenu: inContextMenu) { run(action) }
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
    /// What the history search last said to VoiceOver.
    @State private var foundSaid: String?

    /// The matches listed under the search; how many there are in all is said.
    private static let matchesShown = 5

    var body: some View {
        SheetLayout(
            title: "Add an Adult",
            message: "For an adult who would rather not sign in at the tablet. They are signed in for today as if they had."
        ) {
            Section {
                if let known {
                    LabeledContent("From the adult history") {
                        HStack {
                            Text("\(known.shownFullName), \(known.unitDisplay)")
                            Button("Start Over") { startOver() }
                                .buttonStyle(.link)
                        }
                    }
                } else {
                    TextField("Signed in before?", text: $search, prompt: Text("Search the adult history by name, email or unit"))
                    ForEach(model.event?.historyMatches(for: search, limit: Self.matchesShown) ?? []) { match in
                        Button {
                            fill(from: match)
                        } label: {
                            HStack {
                                Text(match.shownFullName)
                                Text(match.unitDisplay).foregroundStyle(.secondary)
                                Spacer()
                                Text(match.email).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Fill in the form from \(match.shownFullName)'s record")
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
                        SheetProblem(text: problem)
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
        // How many in the history match, said once typing pauses, since the
        // list shows only the first few.
        .task(id: search) {
            guard known == nil, !search.trimmingCharacters(in: .whitespaces).isEmpty else {
                foundSaid = nil
                return
            }
            guard (try? await Task.sleep(for: .milliseconds(400))) != nil, let event = model.event else { return }
            let total = event.historyMatches(for: search, limit: .max).count
            let text = SearchSpeech.historyFound(total: total, shown: min(total, Self.matchesShown))
            guard text != foundSaid else { return }
            foundSaid = text
            Speech.say(text)
        }
    }

    private func fill(from match: Adult) {
        known = match
        first = match.first.shownValue
        last = match.last.shownValue
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

/// A board role, with Chair made easy to spot by its weight, and
/// Unavailable in the role menus' words.
struct RoleText: View {
    let role: String

    var body: some View {
        switch BoardRole(rawValue: role) {
        case .chair:
            Text("Chair").fontWeight(.semibold)
        case .unavailable:
            Text("No Thanks").foregroundStyle(.secondary)
        default:
            Text(role)
        }
    }
}
