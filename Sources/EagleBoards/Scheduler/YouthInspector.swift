import EagleBoardsCore
import SwiftUI

/// Everything about the selected youth, down the right of the window: the
/// board being drawn up for them while they wait, the board sitting once it
/// is seated, the result when it is done, and who introduces them, with their
/// leader and parents.
struct YouthInspector: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent
    let steps: StepFocus

    var body: some View {
        if let youth = model.selectedYouth {
            ScrollViewReader { scroller in
                TimelineView(.everyMinute) { timeline in
                    Form {
                        YouthHeader(youth: youth, event: event, now: timeline.date)
                        switch youth.status {
                        case .registered, .verified, nil:
                            DraftBoardSections(youth: youth, event: event, steps: steps)
                        case .seated, .inProgress:
                            SittingBoardSection(youth: youth, event: event, now: timeline.date, steps: steps)
                        case .completed, .postponed:
                            ResultSection(youth: youth, event: event)
                        }
                        WithThemSection(youth: youth, event: event)
                            .id(WithThemSection.scrollID)
                    }
                    .formStyle(.grouped)
                    // A seating note that appears while the board is drawn
                    // up is said. On the form, not the board's section,
                    // which hands its modifiers to every row and would say
                    // it once a row. Another youth starts a fresh view (the
                    // `.id` below), and a board just begun has no notes
                    // before it, so those already there are only shown.
                    .onChange(of: DraftBoardSections.spokenNotes(for: youth, model: model, event: event)) { previous, current in
                        guard let previous, let current else { return }
                        Speech.say(SeatingReview.newlySpoken(current, since: previous))
                    }
                }
                // Board › Locate Leader and Parents. Checked on appearing too:
                // showing the inspector, or selecting another youth, draws it
                // afresh. The scroll waits a turn for the form's layout.
                .onChange(of: model.locateRequested, initial: true) {
                    guard model.locateRequested else { return }
                    model.locateRequested = false
                    Task { scroller.scrollTo(WithThemSection.scrollID, anchor: .top) }
                }
            }
            .id(youth.id)
        } else {
            ContentUnavailableView("No Youth Selected", systemImage: "person.crop.circle",
                                   description: Text("Select a youth to draw up their board, or to see how it went."))
        }
    }
}

private struct YouthHeader: View {
    let youth: Scout
    let event: BoardEvent
    let now: Date

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(youth.shownFullName).font(.title2.bold()).heading(.h1)
                    Spacer()
                    StatusBadge(statusText: youth.statusText)
                }
                let detail = [youth.regNum, youth.unitDisplay, youth.boardType?.label ?? youth.boardTypeText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                Text(detail)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(detail.spokenList)
                if let minutes = youth.minutesSinceLastUpdate(now: now) {
                    Text(youth.timeText(minutes: minutes)).font(.callout).foregroundStyle(.secondary)
                }
            }
            if !youth.leader.isEmpty {
                LabeledContent("Leader", value: youth.leader.shownValue)
            }
        }
    }
}

// MARK: - Waiting: the board being drawn up

private struct DraftBoardSections: View {
    @Environment(AppModel.self) private var model
    let youth: Scout
    let event: BoardEvent
    let steps: StepFocus
    @State private var isTargeted = false

    var body: some View {
        if let draft = model.draft, let boardType = youth.boardType {
            let members = model.draftMembers(for: youth.id)
            let chairID = draft.chair(among: members, for: boardType)
            let notes = Self.notes(for: youth, draft: draft, members: members, event: event)

            Section {
                Picker("Room", selection: Binding(get: { draft.roomID }, set: { model.setDraftRoom($0) })) {
                    Text("None").tag(Room.ID?.none)
                    ForEach(roomChoices(for: boardType)) { choice in
                        Text(roomLabel(choice)).accessibilityLabel(roomLabel(choice).spokenList).tag(Optional(choice.id))
                    }
                }
                ForEach(members) { member in
                    MemberRow(
                        member: member, youth: youth, boardType: boardType,
                        isChair: member.id == chairID, focus: steps.focus,
                        makeChair: { model.makeChair(member.id) },
                        remove: { remove(member.id, from: members) })
                }
                if members.isEmpty {
                    // The list to add from, by its heading, not by where it is.
                    Text("No one yet. Click someone under Free for a \(boardType.label), drag them here, "
                        + "or use Fill the Rest.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Board")
                    Spacer()
                    Text(sizeText(members.count, boardType)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .heading(.h2)
            } footer: {
                ReviewNotes(problems: notes.problems, warnings: notes.warnings)
            }
            // Outlined as well as tinted while adults are dragged over it, as a
            // room card is for a youth: the tint alone is faint.
            .listRowBackground(isTargeted ? DropHighlight() : nil)
            .dropDestination(for: String.self) { items, _ in
                let ids = DragPayload.adultIDs(in: items)
                model.addToDraft(ids)
                return !ids.isEmpty
            } isTargeted: { isTargeted = $0 }

            Section {
                HStack {
                    Button("Start Over") { model.suggestBoard() }
                        .help("Replace this board with a proposed chair, members, and room")
                    Button("Fill the Rest") { model.fillDraft() }
                        .help("Keep who you chose and add a chair and members to complete the board")
                    Button("Clear Board") {
                        steps.run(.clearBoard, then: .findAdult, landed: { model.draft?.memberIDs.isEmpty != false }) {
                            model.clearDraft()
                        }
                    }
                    .focused(steps.focus, equals: .clearBoard)
                    .disabled(members.isEmpty)
                }
                // A refresh can take off the member whose − has the focus:
                // the focus goes on, as − itself sends it. On this one row,
                // not the section, which hands its modifiers to every row.
                .onChange(of: members.map(\.id)) { old, new in
                    if case .remove(let id)? = steps.focus.wrappedValue, !new.contains(id) {
                        steps.focus.wrappedValue = ListFocus.row(id, in: old, becoming: new).map { .remove($0) } ?? .findAdult
                    }
                }
                HStack {
                    // Not styled destructive: Edit › Undo brings them back.
                    Button("Postpone") {
                        steps.run(.postpone, then: .youthList) { model.postpone() }
                    }
                    .focused(steps.focus, equals: .postpone)
                    .buttonStyle(.link)
                    .help("Put this board off to another event, as when the paperwork is not ready")
                    Spacer()
                    Button(BoardStep.seat.title) {
                        steps.run(.seat, then: .startReview) { model.beginSeating() }
                    }
                    .focused(steps.focus, equals: .seat)
                    .buttonStyle(.borderedProminent)
                    .disabled(members.isEmpty || model.sheet != nil)
                }
            }

            FreeAdultsSection(youth: youth, event: event, boardType: boardType, draftIDs: Set(draft.memberIDs),
                              focus: steps.focus)
        } else if youth.boardType == nil {
            Section {
                NoticeLabel.warning(SeatingReview.noBoardType(youth.shownFullName))
            }
        } else if youth.status == nil {
            Section {
                NoticeLabel.warning("\(youth.shownFullName)'s status is not one Eagle Boards knows, so it cannot draw up a board. "
                    + "The Youth page shows it in the Status column.")
            }
        } else {
            // No board yet, so there is nothing to start over.
            Section {
                Button("Suggest Board") {
                    steps.run(.suggestBoard, then: model.draftMembers(for: youth.id).isEmpty ? .findAdult : .seat,
                              landed: { model.draft != nil }) {
                        model.suggestBoard()
                    }
                }
                .focused(steps.focus, equals: .suggestBoard)
            }
        }
    }

    /// − on a member. With the focus on it, the focus goes to the next
    /// member's −, or to Find an adult once the board is empty.
    private func remove(_ id: Adult.ID, from members: [Adult]) {
        let hadFocus = steps.focus.wrappedValue == .remove(id)
        let next = ListFocus.row(after: id, in: members.map(\.id))
        model.removeFromDraft([id])
        if hadFocus {
            steps.focus.wrappedValue = next.map { .remove($0) } ?? .findAdult
        }
    }

    /// What the board being drawn up shows under it: the draft's own
    /// problems and the review's, each once, then the review's warnings. An
    /// empty board is one being picked, not a mistake: what stops it is
    /// said only once someone is on it.
    static func notes(for youth: Scout, draft: BoardDraft, members: [Adult], event: BoardEvent)
        -> (problems: [String], warnings: [SeatingReview.Warning]) {
        let review = SeatingReview(scout: youth, members: members, room: draft.roomID.flatMap { event.room(id: $0) })
        return ((draft.problems + (members.isEmpty ? [] : review.blockingProblems)).uniqued, review.warnings)
    }

    /// The same notes as VoiceOver reads them. Nil while the youth has no
    /// board being drawn up.
    static func spokenNotes(for youth: Scout, model: AppModel, event: BoardEvent) -> [String]? {
        guard youth.status?.isWaitingForBoard ?? true, youth.boardType != nil, let draft = model.draft else { return nil }
        let notes = notes(for: youth, draft: draft, members: model.draftMembers(for: youth.id), event: event)
        return SeatingReview.spoken(problems: notes.problems, warnings: notes.warnings)
    }

    /// Free rooms of the right kind first, then other free rooms.
    private func roomChoices(for boardType: BoardType) -> [Room] {
        let free = event.rooms.filter(\.isFree)
        return free.filter { $0.boardType == boardType } + free.filter { $0.boardType != boardType }
    }

    private func roomLabel(_ room: Room) -> String {
        "\(room.name) · \(room.boardType?.label ?? room.boardTypeText)"
    }

    private func sizeText(_ count: Int, _ boardType: BoardType) -> String {
        let minimum = BoardRules.minimumMembers(for: boardType)
        return count < minimum ? "\(count) of \(minimum) needed" : "\(count) member\(count == 1 ? "" : "s")"
    }
}

/// A member of the board being drawn up, with anything that stops them
/// sitting on it. Only the board's chair reads Chair (SPEC.md D-10); anyone
/// else on it who may chair reads Can Chair, and Make Chair hands it to them.
private struct MemberRow: View {
    let member: Adult
    let youth: Scout
    let boardType: BoardType
    let isChair: Bool
    let focus: FocusState<SchedulerFocus?>.Binding
    let makeChair: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // One element for what the row says; the button stays its own,
            // for Full Keyboard Access and Voice Control.
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(member.shownFullName)
                        AdultMarks(adult: member, youth: youth)
                    }
                    if let busy {
                        // The red symbol says it stops them sitting; red words
                        // would be too faint to read.
                        NoticeLabel.problem(busy).font(.caption)
                    } else {
                        Text(member.unitDisplay).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                role
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(member.spokenRow(youth: youth, place: busy ?? member.unitDisplay, role: roleWords))
            .accessibilityActions {
                if member.canChair(boardType) && !isChair {
                    Button("Make Chair", action: makeChair)
                }
            }
            Button(action: remove) {
                Image(systemName: "minus.circle").memberButtonTarget()
            }
            .focused(focus, equals: .remove(member.id))
            .buttonStyle(.borderless)
            .help("Take \(member.shownFullName) off this board")
            .accessibilityLabel("Remove \(member.shownFullName)")
        }
        .contextMenu {
            if member.canChair(boardType) && !isChair {
                Button("Make Chair", action: makeChair)
            }
        }
    }

    @ViewBuilder
    private var role: some View {
        if isChair {
            RoleText(role: BoardRole.chair.rawValue)
        } else if member.canChair(boardType) {
            Text("Can Chair").foregroundStyle(.secondary)
        } else {
            RoleText(role: member.role(for: boardType)?.rawValue ?? "")
        }
    }

    /// What `role` shows, for VoiceOver.
    private var roleWords: String {
        if isChair { return BoardRole.chair.label }
        if member.canChair(boardType) { return "Can Chair" }
        return member.role(for: boardType)?.label ?? ""
    }

    private var busy: String? {
        if member.isDisabledForToday { return "Gone home" }
        if member.isOnBoard { return "On the board in room \(member.room)" }
        if member.role(for: boardType) == .unavailable { return "No thanks to \(boardType.label)s" }
        return nil
    }
}

extension Image {
    /// An add or remove button's symbol, with room around it to click: a
    /// borderless button is otherwise only as large as the glyph.
    func memberButtonTarget() -> some View {
        frame(width: 24, height: 24).contentShape(Rectangle())
    }
}

/// The board's rows while adults are dragged over it: tinted, and outlined in
/// the accent color.
private struct DropHighlight: View {
    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.12))
            .overlay { Rectangle().strokeBorder(Color.accentColor, lineWidth: 2) }
    }
}

/// Why the board cannot be seated yet, and what Seat Board will ask about.
private struct ReviewNotes: View {
    let problems: [String]
    let warnings: [SeatingReview.Warning]

    var body: some View {
        let unique = problems.uniqued
        if !unique.isEmpty || !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(unique, id: \.self) { problem in
                    NoticeLabel.problem(problem)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SeatingReview.spoken(problem: problem))
                }
                ForEach(warnings) { warning in
                    NoticeLabel.warning(warning.title)
                        .help(warning.detail)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(SeatingReview.spoken(warning: warning))
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Adults free to sit on this kind of board, chairs first. Click one to put
/// them on the board; type to find someone, and Return adds the first found.
private struct FreeAdultsSection: View {
    @Environment(AppModel.self) private var model
    let youth: Scout
    let event: BoardEvent
    let boardType: BoardType
    let draftIDs: Set<Adult.ID>
    let focus: FocusState<SchedulerFocus?>.Binding
    @State private var search = ""

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let free = event.adults
            .filter { $0.canJoin(boardType) && !draftIDs.contains($0.id) }
            .filter { query.isEmpty || $0.shownFullName.localizedCaseInsensitiveContains(query)
                || $0.unitName.localizedCaseInsensitiveContains(query) || $0.unitLabel.localizedCaseInsensitiveContains(query)
                || $0.unitDisplay.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let lhsChairs = lhs.canChair(boardType), rhsChairs = rhs.canChair(boardType)
                if lhsChairs != rhsChairs { return lhsChairs }
                return (lhs.last, lhs.first) < (rhs.last, rhs.first)
            }

        Section {
            TextField("Find an adult", text: $search, prompt: Text("Name or unit"))
                .labelsHidden()
                .focused(focus, equals: .findAdult)
                // Only once something is typed: Return in the empty field
                // would otherwise add whoever heads the list.
                .onSubmit { if !query.isEmpty, let first = free.first { add(first, from: free) } }
                // An adult whose + has the focus can leave the list with no
                // button pressed: put on another board, gone home, or on this
                // one by a refresh. The focus goes to the row in their place.
                // On this one row, not the section, which hands its
                // modifiers to every row.
                .onChange(of: free.map(\.id)) { old, new in
                    if case .add(let id)? = focus.wrappedValue, !new.contains(id) {
                        focus.wrappedValue = ListFocus.row(id, in: old, becoming: new).map { .add($0) } ?? .findAdult
                    }
                }
            if free.isEmpty {
                Text(query.isEmpty ? "Everyone who could sit is on a board." : "No free adult matches.")
                    .foregroundStyle(.secondary)
            }
            ForEach(free) { adult in
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(adult.shownFullName)
                        AdultMarks(adult: adult, youth: youth)
                        Spacer()
                        Text(adult.unitDisplay).font(.caption).foregroundStyle(.secondary)
                        RoleText(role: adult.role(for: boardType)?.rawValue ?? "")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(adult.spokenRow(youth: youth, place: adult.unitDisplay,
                                                        role: adult.role(for: boardType)?.label ?? ""))
                    Button {
                        add(adult, from: free)
                    } label: {
                        Image(systemName: "plus.circle").memberButtonTarget()
                    }
                    .focused(focus, equals: .add(adult.id))
                    .buttonStyle(.borderless)
                    .help("Put \(adult.shownFullName) on this board")
                    .accessibilityLabel("Add \(adult.shownFullName)")
                }
                .contentShape(Rectangle())
                .onTapGesture { add(adult, from: free) }
                .draggable(DragPayload.adult(adult.id))
            }
        } header: {
            Text("Free for a \(boardType.label) (\(free.count))").heading(.h2)
        }
    }

    /// Put them on the board, and clear the search for the next one. With
    /// the focus on their +, the focus goes to the next adult's +, or to Find
    /// an adult once no one is left.
    private func add(_ adult: Adult, from free: [Adult]) {
        let hadFocus = focus.wrappedValue == .add(adult.id)
        let next = ListFocus.row(after: adult.id, in: free.map(\.id))
        model.addToDraft([adult.id])
        search = ""
        if hadFocus {
            focus.wrappedValue = next.map { .add($0) } ?? .findAdult
        }
    }
}

// MARK: - Seated or in review

private struct SittingBoardSection: View {
    @Environment(AppModel.self) private var model
    let youth: Scout
    let event: BoardEvent
    let now: Date
    let steps: StepFocus

    var body: some View {
        Section {
            LabeledContent("Room") {
                HStack {
                    Text(youth.room)
                    if let minutes = youth.minutesSinceLastUpdate(now: now),
                       let state = RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: minutes, config: event.config) {
                        TimerBadge(minutes: minutes, state: state)
                    }
                }
            }
            LabeledContent("Chair", value: youth.boardChair.shownValue)
            LabeledContent("Members") {
                Text(youth.boardMemberNames(among: event.adults).joined(separator: ", ")).multilineTextAlignment(.trailing)
            }
            Button("Change Members…") { model.beginChangingMembers() }
                .help("Remove or add members without resetting the room timer")
        } header: {
            Text("Board").heading(.h2)
        }
        Section {
            HStack {
                Button("Reset Board") {
                    steps.run(.resetBoard, then: .youthList) { model.reset() }
                }
                .focused(steps.focus, equals: .resetBoard)
                .help("Undo seating: the youth waits again and the room and members are freed")
                Spacer()
                if youth.status == .seated {
                    Button(BoardStep.startReview.title) {
                        steps.run(.startReview, then: .complete) { model.confirmStartReview() }
                    }
                    .focused(steps.focus, equals: .startReview)
                    .buttonStyle(.borderedProminent)
                    .help("Bring the youth into the room, once the members have finished reading")
                } else {
                    Button(BoardStep.complete.title) {
                        steps.run(.complete, then: .youthList) { model.beginCompleting() }
                    }
                    .focused(steps.focus, equals: .complete)
                    .buttonStyle(.borderedProminent)
                    .help("Finish the review and record the result")
                }
            }
        }
    }
}

// MARK: - Finished

private struct ResultSection: View {
    let youth: Scout
    let event: BoardEvent

    var body: some View {
        Section {
            if youth.status == .postponed {
                Text("Put off to another event. Edit › Undo brings them back to the waiting list, if it was the last thing done.")
                    .foregroundStyle(.secondary)
            }
            if youth.status == .completed {
                LabeledContent("Result", value: BoardResult(rawValue: youth.result)?.label ?? youth.result)
            }
            if !youth.boardChair.isEmpty {
                LabeledContent("Chair", value: youth.boardChair.shownValue)
            }
            if !youth.boardMembers.isEmpty {
                LabeledContent("Members") {
                    Text(youth.boardMemberNames(among: event.adults).joined(separator: ", ")).multilineTextAlignment(.trailing)
                }
            }
            if !youth.notes.isEmpty {
                Text(youth.notes.shownMultilineValue)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(youth.status == .postponed ? "Postponed" : "Result").heading(.h2)
        }
    }
}

// MARK: - Who introduces them, and their leader and parents

/// The adults to fetch: whoever introduces the youth to their board
/// (SPEC.md D-23), then their leader and parents, with where each one is now.
private struct WithThemSection: View {
    /// Where Board › Locate Leader and Parents scrolls the inspector.
    static let scrollID = "withThem"

    @Environment(AppModel.self) private var model
    let youth: Scout
    let event: BoardEvent

    var body: some View {
        let people = AdultLocator.locate(for: youth, among: event.adults)
        let others = event.adults
            .filter { !$0.supports(youth.id) }
            .sorted { ($0.last, $0.first) < ($1.last, $1.first) }
        // The youth's own leaders are usually who introduces them, so their
        // unit comes first, out of a list of every adult at the event.
        let ownUnit = youth.unitName.isEmpty ? [] : others.filter { $0.unitName == youth.unitName }
        let everyoneElse = others.filter { $0.unitName != youth.unitName || youth.unitName.isEmpty }

        Section {
            if people.isEmpty {
                Text(youth.leader.isEmpty
                    ? "No one is linked to introduce \(youth.first.shownValue), and no leader or parent has signed in."
                    : "No one is linked to introduce \(youth.first.shownValue), and their leader, "
                        + "\(youth.leader.shownValue), has not signed in.")
                    .foregroundStyle(.secondary)
            }
            ForEach(people) { match in
                LabeledContent {
                    Text(match.whereabouts)
                } label: {
                    Text(match.adult.shownFullName)
                    Text(match.relation.rawValue)
                }
                .contextMenu {
                    if match.relation == .supporting {
                        unlinkButton(match.adult)
                    }
                }
                // Board › Unlink Introducer is the keyboard's way; this is
                // VoiceOver's, in the Actions menu.
                .accessibilityActions {
                    if match.relation == .supporting {
                        unlinkButton(match.adult)
                    }
                }
            }
        } header: {
            HStack {
                Text("With Them").heading(.h2)
                Spacer()
                Menu {
                    if !ownUnit.isEmpty {
                        Section(youth.unitDisplay) {
                            ForEach(ownUnit) { linkItem($0) }
                        }
                        if !everyoneElse.isEmpty {
                            Divider()
                        }
                    }
                    ForEach(everyoneElse) { linkItem($0) }
                } label: {
                    Label("Link an Adult", systemImage: "link")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(others.isEmpty)
                .help("Link the adult who will introduce \(youth.first.shownValue) to their board")
            }
        }
    }

    private func unlinkButton(_ adult: Adult) -> some View {
        Button("Unlink from \(youth.shownFullName)") {
            model.setSupporting(false, adultID: adult.id, scoutID: youth.id)
        }
    }

    /// One adult in Link an Adult, with their unit, as Windows lists them,
    /// and read with a comma for the dot.
    private func linkItem(_ adult: Adult) -> some View {
        let shown = adult.unitDisplay.isEmpty ? adult.shownFullName : "\(adult.shownFullName) · \(adult.unitDisplay)"
        return Button {
            model.setSupporting(true, adultID: adult.id, scoutID: youth.id)
        } label: {
            Text(shown).accessibilityLabel(shown.spokenList)
        }
    }
}

extension Array where Element == String {
    /// Each one once, in order: a draft's problem can also be the review's.
    var uniqued: [String] {
        reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
