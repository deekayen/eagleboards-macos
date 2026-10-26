import EagleBoardsCore
import SwiftUI

/// Every adult who has signed in at this event, the Adults page (SPEC.md P-6).
/// Select several with Command or Shift to mark them gone home or back
/// together. Their details are edited in place, and it is here that someone is
/// promoted to Chair; a changed cell is saved as it is left and stays off the
/// Undo stack, and a change to their name, unit, contact or roles reaches the
/// adult history too. Their room is read-only: it changes only through the
/// Event page's steps. The page has no inspector and no board in view, so
/// nothing here puts an adult on a board; that is done on the Event page.
/// Add Adult…, at the foot of the list, in the Adult menu, or by
/// double-clicking below the last row, signs in someone who would rather not
/// use the tablet.
struct AdultList: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent
    let focus: FocusState<SchedulerFocus?>.Binding

    /// The sortable columns, as headed below, for View › Sort By.
    static let order = TableOrder<Adult>([
        .init("Status", \.room), .init("Last Name", \.last), .init("First Name", \.first),
        .init("Unit Type", \.unitType), .init("Unit", \.unit), .init("Final Board Role", \.finalBoardRoleText),
        .init("Proposal Review Role", \.projectReviewRoleText), .init("Wood Badge", \.woodBadge),
        .init("Introduces", \.supporting), .init("Email", \.email), .init("Phone", \.phone),
    ])

    var body: some View {
        @Bindable var model = model
        let sortOrder = model.sortOrder(for: .adults, Self.order)
        let rows = event.adults
            .filter { matches(model.searchText, $0) }
            .sorted(using: sortOrder.wrappedValue)

        Table(of: Adult.self, selection: $model.selectedAdultIDs, sortOrder: sortOrder) {
            Group {
                TableColumn("Status", value: \Adult.room) { adult in
                    AdultStatusLabel(adult: adult)
                        .adultRowStyle(adult)
                }
                .width(min: 80, ideal: 110, max: 150)
                TableColumn("Last Name", value: \Adult.last) { adult in
                    EditableText(adult.last.shownValue, name: "Last name") { value in edit(adult) { $0.last = value } }
                        .adultRowStyle(adult)
                }
                TableColumn("First Name", value: \Adult.first) { adult in
                    EditableText(adult.first.shownValue, name: "First name") { value in edit(adult) { $0.first = value } }
                        .adultRowStyle(adult)
                }
                TableColumn("Unit Type", value: \Adult.unitType) { adult in
                    EditableChoice(adult.unitType, choices: RecordChoices.adultUnitTypes, name: "Unit type") { value in
                        edit(adult) { $0.unitType = value }
                    }
                    .adultRowStyle(adult)
                }
                .width(min: 60, ideal: 80, max: 110)
                TableColumn("Unit", value: \Adult.unit) { adult in
                    EditableText(adult.unit, name: "Unit number") { value in edit(adult) { $0.unit = value } }
                        .adultRowStyle(adult)
                }
                .width(min: 40, ideal: 50, max: 70)
            }
            Group {
                TableColumn("Final Board Role", value: \Adult.finalBoardRoleText) { adult in
                    RoleChoice(role: adult.finalBoardRoleText, name: "Final Board role") { value in
                        edit(adult) { $0.finalBoardRoleText = value }
                    }
                    .adultRowStyle(adult)
                }
                .width(min: 92, ideal: 106, max: 140)
                TableColumn("Proposal Review Role", value: \Adult.projectReviewRoleText) { adult in
                    RoleChoice(role: adult.projectReviewRoleText, name: "Proposal Review role") { value in
                        edit(adult) { $0.projectReviewRoleText = value }
                    }
                    .adultRowStyle(adult)
                }
                .width(min: 120, ideal: 132, max: 160)
                // Volunteering toward a Wood Badge ticket item.
                TableColumn("Wood Badge", value: \Adult.woodBadge) { adult in
                    WoodBadgeChoice(value: adult.woodBadge) { value in edit(adult) { $0.woodBadge = value } }
                        .adultRowStyle(adult)
                }
                .width(min: 74, ideal: 88, max: 110)
                // Whom they introduce to their board of review (SPEC.md D-23).
                TableColumn("Introduces", value: \Adult.supporting) { adult in
                    let names = supportedNames(adult)
                    CellText(names).foregroundStyle(.secondary).help(names)
                        .adultRowStyle(adult)
                }
            }
            Group {
                TableColumn("Email", value: \Adult.email) { adult in
                    EditableText(adult.email, name: "Email") { value in edit(adult) { $0.email = value } }
                        .adultRowStyle(adult)
                }
                TableColumn("Phone", value: \Adult.phone) { adult in
                    EditableText(adult.phone, name: "Phone") { value in edit(adult) { $0.phone = value } }
                        .adultRowStyle(adult)
                }
            }
        } rows: {
            ForEach(rows) { TableRow($0) }
        }
        .focused(focus, equals: .table(.adults))
        // Return in the search: the first adult found, with the focus.
        .onChange(of: model.searchSubmitted) {
            guard let first = rows.first else { return }
            model.selectedAdultIDs = [first.id]
            focus.wrappedValue = .table(.adults)
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
            // Double-clicking below the last row adds someone. A row's details
            // are edited in place, so double-clicking one does nothing more.
            if ids.isEmpty {
                model.present(.addAdult)
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

extension View {
    /// A busy adult's row in secondary text, and a gone-home adult's in
    /// secondary italics, as Windows sets them apart for scanning; the Status
    /// column says which in words. A name or note being typed in is upright
    /// (`EditableText`). Never a conditional modifier, which would rebuild a
    /// cell, and a cell being edited with it, when the adult is seated or
    /// freed.
    func adultRowStyle(_ adult: Adult) -> some View {
        foregroundStyle(adult.isOnBoard || adult.isDisabledForToday ? .secondary : .primary)
            .italic(adult.isDisabledForToday)
            .environment(\.rowIsItalic, adult.isDisabledForToday)
    }
}

/// Free, on a board in a room, or gone home: in words and a symbol, not
/// only a color.
struct AdultStatusLabel: View {
    let adult: Adult

    var body: some View {
        if adult.isDisabledForToday {
            Label("Gone home", systemImage: "moon.zzz")
                .foregroundStyle(.secondary)
                .help("Gone home. Adult › Mark Back brings them back.")
        } else if adult.isOnBoard {
            Label("Room \(adult.room)", systemImage: "person.3.fill")
                .help("On the board in room \(adult.room)")
        } else {
            Label("Free", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

/// What can be done to adults: the Adult menu, and the context menu on their
/// rows. Acting on rows that are not selected selects them first.
///
/// The adults to act on are those picked on the Adults page. Putting an adult
/// on a board, handing them the chair, and linking them to a youth as their
/// introducer all need the youth's board in view, which is the Event page's
/// inspector, and the Event page has no table of adults to pick from, so they
/// are the inspector's and not here.
///
/// The Adult menu keeps Mark Gone Home and Mark Back, dimmed where they do not
/// apply. The context menu lists only what applies: Mark Gone Home or Mark Back
/// and, for one adult, Delete Adult….
struct AdultActionButtons: View {
    let model: AppModel
    /// Nil acts on the selected adults.
    var adultIDs: Set<Adult.ID>?
    var inContextMenu = false

    var body: some View {
        let ids = adultIDs ?? (model.page.listsAdults ? model.selectedAdultIDs : [])
        let adults = model.event?.adults.filter { ids.contains($0.id) } ?? []
        let single = adults.count == 1 ? adults.first : nil
        let canMarkGoneHome = adults.contains(where: \.isAvailable)
        let canMarkBack = adults.contains(where: \.isDisabledForToday)

        command("Mark Gone Home", applies: canMarkGoneHome) { model.setAvailable(false) }
        command("Mark Back", applies: canMarkBack) { model.setAvailable(true) }
        if inContextMenu, let single {
            if canMarkGoneHome || canMarkBack {
                Divider()
            }
            Button("Delete Adult…", role: .destructive) { model.confirmDeleteAdult(single.id) }
        }
    }

    private func command(_ title: String, applies: Bool, _ action: @escaping @MainActor () -> Void) -> MenuCommand {
        MenuCommand(title, applies: applies, inContextMenu: inContextMenu) { run(action) }
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

    /// Where Return and the arrow keys take the cursor: the history search,
    /// a match under it, or First name once the form is filled in.
    private enum Field: Hashable {
        case search
        case match(Adult.ID)
        case first
    }

    @FocusState private var field: Field?

    /// The matches listed under the search; how many there are in all is said.
    private static let matchesShown = 5

    var body: some View {
        let matches = known == nil ? model.event?.historyMatches(for: search, limit: Self.matchesShown) ?? [] : []
        SheetLayout(
            title: "Add an Adult",
            message: "Sign in an adult who would rather not use the tablet. "
                + "They are signed in for today, as if they had used it."
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
                    TextField("Signed in before?", text: $search, prompt: Text("Search the adult history by name, email, or unit"))
                        .focused($field, equals: .search)
                        .onSubmit { submitSearch(matches) }
                    ForEach(matches) { match in
                        HStack {
                            Text(match.shownFullName)
                            Text(match.unitDisplay).foregroundStyle(.secondary)
                            Spacer()
                            Text(match.email).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { fill(from: match) }
                        // Return in the search comes here, so a match takes
                        // the focus with Keyboard navigation off too.
                        .focusable(interactions: .edit)
                        .focused($field, equals: .match(match.id))
                        .onKeyPress(.return) {
                            fill(from: match)
                            return .handled
                        }
                        .onKeyPress(.space) {
                            fill(from: match)
                            return .handled
                        }
                        .onMoveCommand { move($0, from: match.id, in: matches) }
                        .help("Fill in the form from \(match.shownFullName)'s record")
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { fill(from: match) }
                    }
                }
            }
            Section {
                TextField("First name", text: $first)
                    .focused($field, equals: .first)
                TextField("Last name", text: $last)
                Picker("Unit type", selection: $unitType) {
                    ForEach(UnitType.allCases) { Text($0.rawValue).tag($0) }
                }
                if unitType.hasUnitNumber {
                    TextField("Unit number", text: $unit)
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
                    // Why Add Adult is dimmed until both names are typed.
                    Text("First and last name are required. Everything else is optional.")
                        .foregroundStyle(.secondary)
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
            .keyboardShortcut(inSearch ? nil : .defaultAction)
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

    /// Return in the search or on a match fills the form from the history.
    /// It never presses Add Adult, which would add names typed by hand.
    private var inSearch: Bool {
        switch field {
        case .search, .match: true
        case .first, nil: false
        }
    }

    /// Return in the search: the form filled in from the one match, or the
    /// first of several, to choose from with the arrow keys.
    private func submitSearch(_ matches: [Adult]) {
        if matches.count == 1, let match = matches.first {
            fill(from: match)
        } else if let first = matches.first {
            field = .match(first.id)
        }
    }

    /// Up and Down through the matches; Up from the first goes back to the
    /// search.
    private func move(_ direction: MoveCommandDirection, from id: Adult.ID, in matches: [Adult]) {
        guard let index = matches.firstIndex(where: { $0.id == id }) else { return }
        switch direction {
        case .up: field = index == 0 ? .search : .match(matches[index - 1].id)
        case .down where index + 1 < matches.count: field = .match(matches[index + 1].id)
        default: break
        }
    }

    /// The search and its matches give way to the record's name, so the
    /// cursor goes on to First name.
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
        field = .first
    }

    /// The form emptied, and the search back in place of the record's name,
    /// with the cursor in it.
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
        // A turn later, once the search is drawn again.
        Task { field = .search }
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
