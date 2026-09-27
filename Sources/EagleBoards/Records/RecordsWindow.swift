import EagleBoardsCore
import SwiftUI
import UniformTypeIdentifiers

/// Every record behind the evening, for looking things up and fixing them:
/// correcting a name, promoting someone to Chair, or deleting a duplicate.
struct RecordsWindow: View {
    @Environment(AppModel.self) private var model

    enum Kind: String, CaseIterable, Identifiable {
        case youth = "Youth"
        case scheduled = "Pre-Registered"
        case adults = "Adults"
        case history = "Adult History"
        case rooms = "Rooms"
        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .youth: "person.crop.circle"
            case .scheduled: "calendar"
            case .adults: "person.2"
            case .history: "clock.arrow.circlepath"
            case .rooms: "door.left.hand.closed"
            }
        }
    }

    @State private var kind: Kind = .youth
    @State private var search = ""
    @State private var showsInspector = true

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Kind?>(get: { kind }, set: { if let chosen = $0 { kind = chosen } })) {
                Section("This Event") {
                    row(.youth)
                    row(.scheduled)
                    row(.adults)
                    row(.rooms)
                }
                Section("All Events") {
                    row(.history)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
        } detail: {
            Group {
                if let night = model.night {
                    switch kind {
                    case .youth: YouthRecords(night: night, scheduled: false, search: search, showsInspector: $showsInspector)
                    case .scheduled: YouthRecords(night: night, scheduled: true, search: search, showsInspector: $showsInspector)
                    case .adults: AdultRecords(night: night, history: false, search: search, showsInspector: $showsInspector)
                    case .history: AdultRecords(night: night, history: true, search: search, showsInspector: $showsInspector)
                    case .rooms: RoomRecords(night: night, search: search)
                    }
                } else {
                    ContentUnavailableView("No event is open", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("Choose a data folder in the Eagle Boards window first."))
                }
            }
            .navigationTitle(kind.rawValue)
            .navigationSubtitle(model.night?.night ?? "")
        }
        .frame(minWidth: 820, minHeight: 480)
        .searchable(text: $search, placement: .toolbar, prompt: "Name, email or unit")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    export()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .help("Save this list as a spreadsheet (CSV)")
                .disabled(model.night == nil)
            }
            if kind != .rooms {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsInspector.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.trailing")
                    }
                    .help("Show or hide the record editor")
                }
            }
        }
        .messageAlert()
    }

    private func row(_ kind: Kind) -> some View {
        Label(kind.rawValue, systemImage: kind.symbolName)
            .badge(count(kind))
            .tag(kind)
    }

    private func count(_ kind: Kind) -> Int {
        guard let night = model.night else { return 0 }
        switch kind {
        case .youth: return night.scouts.count
        case .scheduled: return night.scheduledScouts.count
        case .adults: return night.adults.count
        case .history: return night.adultHistory.count
        case .rooms: return night.rooms.count
        }
    }

    private func export() {
        guard let night = model.night else { return }
        let text: String
        switch kind {
        // A youth's birthdate or phone number on file is not exported
        // (SPEC.md D-7, D-8).
        case .youth: text = CSVFile.render(night.scouts.map(\.forExport))
        case .scheduled: text = CSVFile.render(night.scheduledScouts.map(\.forExport))
        case .adults: text = CSVFile.render(night.adults)
        case .history: text = CSVFile.render(night.adultHistory)
        case .rooms: text = CSVFile.render(night.rooms)
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(kind.rawValue) \(night.night).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = "This list holds personal information. Keep the file somewhere private."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            model.message = AppModel.Message(title: "Could not save the list", text: error.localizedDescription)
        }
    }
}

private func matches(_ search: String, _ values: String...) -> Bool {
    let query = search.trimmingCharacters(in: .whitespaces)
    return query.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(query) }
}

// MARK: - Youth

private struct YouthRecords: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    let scheduled: Bool
    let search: String
    @Binding var showsInspector: Bool
    @State private var selection: Scout.ID?
    @State private var sortOrder = [KeyPathComparator(\Scout.last)]

    var body: some View {
        let rows = (scheduled ? night.scheduledScouts : night.scouts)
            .filter { matches(search, $0.first, $0.last, $0.email, $0.unitName) }
            .sorted(using: sortOrder)
        Group {
            // Two tables rather than one with conditional columns, which
            // would need macOS 14.4.
            if scheduled {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Last", value: \.last)
                    TableColumn("First", value: \.first)
                    TableColumn("Unit", value: \.unitName) { Text($0.unitDisplay) }
                    TableColumn("Board", value: \.boardTypeText) { Text($0.boardType?.label ?? $0.boardTypeText) }
                    TableColumn("Email", value: \.email)
                    TableColumn("Leader", value: \.leader)
                }
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Last", value: \.last)
                    TableColumn("First", value: \.first)
                    TableColumn("Unit", value: \.unitName) { Text($0.unitDisplay) }
                    TableColumn("Board", value: \.boardTypeText) { Text($0.boardType?.label ?? $0.boardTypeText) }
                    TableColumn("Status", value: \.statusRank) { StatusBadge(statusText: $0.statusText) }
                    TableColumn("Result", value: \.result)
                    TableColumn("Email", value: \.email)
                    TableColumn("Leader", value: \.leader)
                }
            }
        }
        .inspector(isPresented: $showsInspector) {
            Group {
                if let id = selection, let youth = (scheduled ? night.scheduledScouts : night.scouts).first(where: { $0.id == id }) {
                    RecordEditor(record: youth, fields: scheduled ? Self.scheduledFields : Self.youthFields, noun: "youth") { edited in
                        try night.updateYouth(edited, scheduled: scheduled)
                    } delete: {
                        try night.deleteYouth(id: id, scheduled: scheduled)
                        selection = nil
                    }
                    .id(id)
                } else {
                    ContentUnavailableView("Select a youth", systemImage: "person.crop.rectangle")
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320)
        }
    }

    static let boardTypes = BoardType.allCases.map { ($0.rawValue, $0.label) }
    static let unitTypes = UnitType.youthChoices.map { ($0.rawValue, $0.rawValue) }

    static let youthFields: [FieldSpec] = [
        .init("First", "First name"), .init("Last", "Last name"),
        .init("Email", "Email"),
        .init("UnitType", "Unit type", .choice(unitTypes)), .init("Unit", "Unit #"),
        .init("Leader", "Leader"),
        .init("BoardType", "Board", .choice(boardTypes)),
        .init("RegNum", "Sign-in #", .readOnly), .init("RegTime", "Signed in", .readOnly),
        .init("Status", "Status", .choice(BoardStatus.recordsChoices.map { ($0.rawValue, $0.label) })),
        .init("Room", "Room", .readOnly),
        .init("Result", "Result", .choice([("", "None")] + BoardResult.allCases.map { ($0.rawValue, $0.label) })),
        // Editable so a result recorded against the wrong youth can be moved to
        // the one the board actually reviewed, with the board that did it.
        .init("BoardChair", "Chair"), .init("BoardMembers", "Members"),
        .init("Notes", "Notes", .multiline),
    ]

    static let scheduledFields: [FieldSpec] = [
        .init("First", "First name"), .init("Last", "Last name"),
        .init("Email", "Email"),
        .init("UnitType", "Unit type", .choice(unitTypes)), .init("Unit", "Unit #"),
        .init("Leader", "Leader"),
        .init("BoardType", "Board", .choice(boardTypes)),
    ]
}

// MARK: - Adults

private struct AdultRecords: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    let history: Bool
    let search: String
    @Binding var showsInspector: Bool
    @State private var selection: Adult.ID?
    @State private var sortOrder = [KeyPathComparator(\Adult.last)]

    var body: some View {
        let rows = (history ? night.adultHistory : night.adults)
            .filter { matches(search, $0.first, $0.last, $0.email, $0.unitName) }
            .sorted(using: sortOrder)
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Last", value: \.last)
            TableColumn("First", value: \.first)
            TableColumn("Unit", value: \.unitName) { Text($0.unitDisplay) }
            TableColumn("Final", value: \.finalBoardRoleText) { RoleText(role: $0.finalBoardRoleText) }
            TableColumn("Project", value: \.projectReviewRoleText) { RoleText(role: $0.projectReviewRoleText) }
            // One column that means "Room" tonight and "Nights served" in the
            // history, rather than conditional columns (macOS 14.4 and later).
            TableColumn(history ? "Events" : "Room", value: \.room) { adult in
                if history {
                    Text("\(adult.boardHistory.filter { $0 == "(" }.count)")
                        .monospacedDigit()
                        .help(adult.boardHistory)
                } else {
                    Text(adult.isDisabledForTonight ? "Off today" : adult.room)
                }
            }
            TableColumn("Email", value: \.email)
            TableColumn("Phone", value: \.phone)
        }
        .inspector(isPresented: $showsInspector) {
            Group {
                if let id = selection, let adult = (history ? night.adultHistory : night.adults).first(where: { $0.id == id }) {
                    RecordEditor(record: adult, fields: history ? Self.historyFields : Self.adultFields, noun: "adult") { edited in
                        try night.updateAdult(edited, history: history)
                    } delete: {
                        try night.deleteAdult(id: id, history: history)
                        selection = nil
                    }
                    .id(id)
                } else {
                    ContentUnavailableView("Select an adult", systemImage: "person.crop.rectangle",
                                           description: Text("Promote someone to Chair here by changing their Final or Project role."))
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320)
        }
    }

    static let roles = BoardRole.allCases.map { ($0.rawValue, $0.rawValue) }
    static let unitTypes = UnitType.allCases.map { ($0.rawValue, $0.rawValue) }

    static let adultFields: [FieldSpec] = [
        .init("First", "First name"), .init("Last", "Last name"),
        .init("Email", "Email"), .init("Phone", "Phone"),
        .init("UnitType", "Unit type", .choice(unitTypes)), .init("Unit", "Unit #"),
        .init("FinalBoard", "Final Board", .choice(roles)), .init("ProjectReview", "Proposal Review", .choice(roles)),
        .init("RegTime", "Signed in", .readOnly), .init("Room", "Room", .readOnly),
        .init("WoodBadge", "Wood Badge", .choice([("", "No"), ("Y", "Yes")])),
    ]

    static let historyFields: [FieldSpec] = [
        .init("First", "First name"), .init("Last", "Last name"),
        .init("Email", "Email"), .init("Phone", "Phone"),
        .init("UnitType", "Unit type", .choice(unitTypes)), .init("Unit", "Unit #"),
        .init("FinalBoard", "Final Board", .choice(roles)), .init("ProjectReview", "Proposal Review", .choice(roles)),
        .init("BoardHistory", "Events signed in", .readOnly),
    ]
}

// MARK: - Rooms

private struct RoomRecords: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    let search: String
    @State private var selection: Room.ID?
    /// The room whose Rename sheet is open, wrapped so .sheet(item:) can present it.
    @State private var renaming: RenamingRoom?

    private struct RenamingRoom: Identifiable {
        let id: String
    }

    var body: some View {
        let rows = night.rooms.filter { matches(search, $0.name, $0.scoutName, $0.leaderNames) }
        Table(rows, selection: $selection) {
            TableColumn("Room", value: \.name)
            TableColumn("Used for") { room in
                Picker("Used for", selection: Binding(
                    get: { room.boardType ?? .finalBoard },
                    set: { newType in model.attempt("Could not change the room") { try night.setBoardType(newType, forRoom: room.id) } }
                )) {
                    ForEach(BoardType.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
            }
            TableColumn("Youth", value: \.scoutName)
            TableColumn("Board") { Text($0.leaderNames.withListSeparators) }
        }
        .contextMenu(forSelectionType: Room.ID.self) { ids in
            if let id = ids.first {
                Button("Rename Room…") { renaming = RenamingRoom(id: id) }
                Button("Remove Room", role: .destructive) {
                    model.attempt("Could not remove the room") { try night.removeRoom(id: id) }
                }
            }
        }
        .sheet(item: $renaming) { room in
            RenameRoomSheet(night: night, roomID: room.id, onRenamed: { newID in
                if selection == room.id { selection = newID }
            })
        }
    }
}

// MARK: - Editing one record

struct FieldSpec: Identifiable {
    enum Kind {
        case text
        case multiline
        case choice([(value: String, label: String)])
        case readOnly
    }

    let column: String
    let label: String
    let kind: Kind
    var id: String { column }

    init(_ column: String, _ label: String, _ kind: Kind = .text) {
        self.column = column
        self.label = label
        self.kind = kind
    }
}

/// A form over a copy of one record. Nothing is written until Save.
struct RecordEditor<Record: EventRecord>: View {
    let record: Record
    let fields: [FieldSpec]
    let noun: String
    let save: (Record) throws -> Void
    let delete: () throws -> Void

    @State private var draft: Record
    @State private var problem: String?
    @State private var confirmingDelete = false

    init(record: Record, fields: [FieldSpec], noun: String, save: @escaping (Record) throws -> Void, delete: @escaping () throws -> Void) {
        self.record = record
        self.fields = fields
        self.noun = noun
        self.save = save
        self.delete = delete
        _draft = State(initialValue: record)
    }

    var body: some View {
        Form {
            ForEach(fields) { field in
                row(for: field)
            }
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
            HStack {
                Button("Delete…", role: .destructive) { confirmingDelete = true }
                Spacer()
                Button("Revert") { draft = record }
                    .disabled(draft == record)
                Button("Save") {
                    do {
                        try save(draft)
                        problem = nil
                    } catch {
                        problem = error.localizedDescription
                    }
                }
                .keyboardShortcut("s")
                .disabled(draft == record)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete this \(noun)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                do {
                    try delete()
                } catch {
                    problem = error.localizedDescription
                }
            }
        } message: {
            Text("The record is removed from the file. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func row(for field: FieldSpec) -> some View {
        switch field.kind {
        case .text:
            TextField(field.label, text: binding(field.column))
        case .multiline:
            TextField(field.label, text: binding(field.column), axis: .vertical)
                .lineLimit(3...8)
        case .choice(let options):
            Picker(field.label, selection: binding(field.column)) {
                // Keep an unexpected stored value selectable rather than blank.
                if !options.contains(where: { $0.value == draft[field.column] }) {
                    Text(draft[field.column].isEmpty ? "None" : draft[field.column]).tag(draft[field.column])
                }
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        case .readOnly:
            LabeledContent(field.label, value: draft[field.column].withListSeparators)
        }
    }

    private func binding(_ column: String) -> Binding<String> {
        Binding(get: { draft[column] }, set: { draft[column] = $0 })
    }
}
