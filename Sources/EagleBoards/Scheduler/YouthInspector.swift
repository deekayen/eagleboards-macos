import EagleBoardsCore
import SwiftUI

/// Everything about the selected youth, down the right of the window: the
/// board being drawn up for them while they wait, the board sitting once it
/// is seated, the result when it is done, and who came with them.
struct YouthInspector: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent

    var body: some View {
        if let youth = model.selectedYouth {
            TimelineView(.periodic(from: .now, by: 20)) { timeline in
                Form {
                    YouthHeader(youth: youth, event: event, now: timeline.date)
                    switch youth.status {
                    case .registered, .verified, nil:
                        DraftBoardSections(youth: youth, event: event)
                    case .seated, .inProgress:
                        SittingBoardSection(youth: youth, event: event, now: timeline.date)
                    case .completed, .postponed:
                        ResultSection(youth: youth)
                    }
                    WithThemSection(youth: youth, event: event)
                }
                .formStyle(.grouped)
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
                    Text(youth.fullName).font(.title2.bold())
                    Spacer()
                    StatusBadge(statusText: youth.statusText)
                }
                Text([youth.regNum, youth.unitName, youth.boardType?.label ?? youth.boardTypeText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .foregroundStyle(.secondary)
                if let minutes = youth.minutesSinceLastUpdate(now: now) {
                    Text(timeText(minutes)).font(.callout).foregroundStyle(.secondary)
                }
            }
            if !youth.leader.isEmpty {
                LabeledContent("Leader", value: youth.leader)
            }
        }
    }

    private func timeText(_ minutes: Int) -> String {
        switch youth.status {
        case .seated: "Board convening for \(minutes) min"
        case .inProgress: "In review for \(minutes) min"
        case .completed, .postponed: "Finished \(minutes) min ago"
        default: "Waiting \(minutes) min"
        }
    }
}

// MARK: - Waiting: the board being drawn up

private struct DraftBoardSections: View {
    @Environment(AppModel.self) private var model
    let youth: Scout
    let event: BoardEvent
    @State private var isTargeted = false

    var body: some View {
        if let draft = model.draft, let boardType = youth.boardType {
            let members = model.draftMembers(for: youth.id)
            let room = draft.roomID.flatMap { event.room(id: $0) }
            let review = SeatingReview(scout: youth, members: members, room: room)

            Section {
                Picker("Room", selection: Binding(get: { draft.roomID }, set: { model.setDraftRoom($0) })) {
                    Text("None").tag(Room.ID?.none)
                    ForEach(roomChoices(for: boardType)) { choice in
                        Text(roomLabel(choice)).tag(Optional(choice.id))
                    }
                }
                ForEach(members) { member in
                    MemberRow(member: member, youth: youth, boardType: boardType) {
                        model.removeFromDraft([member.id])
                    }
                }
                if members.isEmpty {
                    Text("Click adults in the list below to add them, or drag them here from the Adults list.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Board")
                    Spacer()
                    Text(sizeText(members.count, boardType)).foregroundStyle(.secondary)
                }
            } footer: {
                // An empty board is one being picked, not a mistake: say what
                // stops it only once someone is on it.
                ReviewNotes(problems: draft.problems + (members.isEmpty ? [] : review.blockingProblems),
                            warnings: review.warnings)
            }
            .listRowBackground(isTargeted ? Color.accentColor.opacity(0.12) : nil)
            .dropDestination(for: String.self) { items, _ in
                let ids = DragPayload.adultIDs(in: items)
                model.addToDraft(ids)
                return !ids.isEmpty
            } isTargeted: { isTargeted = $0 }

            Section {
                HStack {
                    Button("Suggest a Board") { model.suggestBoard() }
                        .help("Replace this board with a proposed chair, members and room")
                    Button("Fill the Rest") { model.fillDraft() }
                        .help("Keep the members you've chosen and add a chair and members to complete the board")
                    Button("Clear") { model.clearDraft() }
                        .disabled(members.isEmpty)
                }
                HStack {
                    Button("Postpone", role: .destructive) { model.postpone() }
                        .buttonStyle(.link)
                        .help("Put this board off to another event, for example when the paperwork is not ready")
                    Spacer()
                    Button(BoardStep.seat.title) { model.beginSeating() }
                        .buttonStyle(.borderedProminent)
                        .disabled(members.isEmpty || model.sheet != nil)
                }
            }

            FreeAdultsSection(youth: youth, event: event, boardType: boardType, draftIDs: Set(draft.memberIDs))
        } else if youth.boardType == nil {
            Section {
                Label("\(youth.fullName) has no board type. Set Final or Project in the Board column of the Youth page.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else {
            Section {
                Button("Suggest a Board") { model.selectYouth(youth.id) }
            }
        }
    }

    /// Free rooms of the right kind first, then other free rooms.
    private func roomChoices(for boardType: BoardType) -> [Room] {
        let free = event.rooms.filter(\.isFree)
        return free.filter { $0.boardType == boardType } + free.filter { $0.boardType != boardType }
    }

    private func roomLabel(_ room: Room) -> String {
        "\(room.name) -- \(room.boardType?.label ?? room.boardTypeText)"
    }

    private func sizeText(_ count: Int, _ boardType: BoardType) -> String {
        let minimum = BoardRules.minimumMembers(for: boardType)
        return count < minimum ? "\(count) of \(minimum) needed" : "\(count) member\(count == 1 ? "" : "s")"
    }
}

/// A member of the board being drawn up, with anything that stops them
/// sitting on it.
private struct MemberRow: View {
    let member: Adult
    let youth: Scout
    let boardType: BoardType
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(member.fullName)
                    AdultMarks(adult: member, youth: youth)
                }
                if let busy {
                    Text(busy).font(.caption).foregroundStyle(.red)
                } else {
                    Text(member.unitLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            RoleText(role: member.role(for: boardType)?.rawValue ?? "")
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Take \(member.fullName) off this board")
            .accessibilityLabel("Remove \(member.fullName)")
        }
    }

    private var busy: String? {
        if member.isDisabledForToday { return "Gone home" }
        if member.isOnBoard { return "On the board in room \(member.room)" }
        if member.role(for: boardType) == .unavailable { return "No thanks to \(boardType.label)s" }
        return nil
    }
}

/// Why the board cannot be seated yet, and what Seat Board will ask about.
private struct ReviewNotes: View {
    let problems: [String]
    let warnings: [SeatingReview.Warning]

    var body: some View {
        let unique = problems.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if !unique.isEmpty || !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(unique, id: \.self) { problem in
                    Label(problem, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                ForEach(warnings) { warning in
                    Label(warning.title, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(warning.detail)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Adults free to sit on this kind of board, chairs first. Click one to put
/// them on the board; type to find someone.
private struct FreeAdultsSection: View {
    @Environment(AppModel.self) private var model
    let youth: Scout
    let event: BoardEvent
    let boardType: BoardType
    let draftIDs: Set<Adult.ID>
    @State private var search = ""

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let free = event.adults
            .filter { $0.canJoin(boardType) && !draftIDs.contains($0.id) }
            .filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query)
                || $0.unitName.localizedCaseInsensitiveContains(query) || $0.unitLabel.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let lhsChairs = lhs.canChair(boardType), rhsChairs = rhs.canChair(boardType)
                if lhsChairs != rhsChairs { return lhsChairs }
                return (lhs.last, lhs.first) < (rhs.last, rhs.first)
            }

        Section("Free for a \(boardType.label) (\(free.count))") {
            TextField("Find an adult", text: $search, prompt: Text("Name or unit"))
                .labelsHidden()
            if free.isEmpty {
                Text(query.isEmpty ? "Everyone who could sit is on a board." : "No free adult matches.")
                    .foregroundStyle(.secondary)
            }
            ForEach(free) { adult in
                HStack(spacing: 6) {
                    Text(adult.fullName)
                    AdultMarks(adult: adult, youth: youth)
                    Spacer()
                    Text(adult.unitLabel).font(.caption).foregroundStyle(.secondary)
                    RoleText(role: adult.role(for: boardType)?.rawValue ?? "")
                    Button {
                        add(adult)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Put \(adult.fullName) on this board")
                    .accessibilityLabel("Add \(adult.fullName)")
                }
                .contentShape(Rectangle())
                .onTapGesture { add(adult) }
                .draggable(DragPayload.adult(adult.id))
            }
        }
    }

    /// Put them on the board, and clear the search for the next one.
    private func add(_ adult: Adult) {
        model.addToDraft([adult.id])
        search = ""
    }
}

// MARK: - Seated or in review

private struct SittingBoardSection: View {
    @Environment(AppModel.self) private var model
    let youth: Scout
    let event: BoardEvent
    let now: Date

    var body: some View {
        Section("Board") {
            LabeledContent("Room") {
                HStack {
                    Text(youth.room)
                    if let minutes = youth.minutesSinceLastUpdate(now: now),
                       let state = RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: minutes, config: event.config) {
                        TimerBadge(minutes: minutes, state: state)
                    }
                }
            }
            LabeledContent("Chair", value: youth.boardChair)
            LabeledContent("Members") {
                Text(youth.boardMembers.withListSeparators).multilineTextAlignment(.trailing)
            }
            Button("Change Members…") { model.beginChangingMembers() }
                .help("Remove or add members without resetting the room timer")
        }
        Section {
            HStack {
                Button("Reset Board") { model.reset() }
                    .help("Undo seating: the youth waits again and the room and members are freed")
                Spacer()
                if youth.status == .seated {
                    Button(BoardStep.startReview.title) { model.confirmStartReview() }
                        .buttonStyle(.borderedProminent)
                        .help("Bring the youth into the room, once the members have finished reading")
                } else {
                    Button(BoardStep.complete.title) { model.beginCompleting() }
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

    var body: some View {
        Section(youth.status == .postponed ? "Postponed" : "Result") {
            if youth.status == .postponed {
                Text("Put off to another event. Edit › Undo brings them back to the waiting list, if it was the last thing done.")
                    .foregroundStyle(.secondary)
            }
            if youth.status == .completed {
                LabeledContent("Result", value: BoardResult(rawValue: youth.result)?.label ?? youth.result)
            }
            if !youth.boardChair.isEmpty {
                LabeledContent("Chair", value: youth.boardChair)
            }
            if !youth.boardMembers.isEmpty {
                LabeledContent("Members") {
                    Text(youth.boardMembers.withListSeparators).multilineTextAlignment(.trailing)
                }
            }
            if !youth.notes.isEmpty {
                Text(youth.notes.withCommasRestored)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Who came with them

/// The adults to fetch: whoever introduces the youth to their board
/// (SPEC.md D-23), then their leader and parents, with where each one is now.
private struct WithThemSection: View {
    @Environment(AppModel.self) private var model
    let youth: Scout
    let event: BoardEvent

    var body: some View {
        let people = AdultLocator.locate(for: youth, among: event.adults)
        let others = event.adults
            .filter { !$0.supports(youth.id) }
            .sorted { ($0.last, $0.first) < ($1.last, $1.first) }

        Section {
            if people.isEmpty {
                Text(youth.leader.isEmpty
                    ? "No one who came with \(youth.first) has signed in."
                    : "\(youth.first)'s leader, \(youth.leader), has not signed in.")
                    .foregroundStyle(.secondary)
            }
            ForEach(people) { match in
                LabeledContent {
                    Text(match.whereabouts)
                } label: {
                    Text(match.adult.fullName)
                    Text(match.relation.rawValue)
                }
                .contextMenu {
                    if match.relation == .supporting {
                        Button("Unlink from \(youth.fullName)") {
                            model.setSupporting(false, adultID: match.adult.id, scoutID: youth.id)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("With Them")
                Spacer()
                Menu {
                    ForEach(others) { adult in
                        Button(adult.fullName) {
                            model.setSupporting(true, adultID: adult.id, scoutID: youth.id)
                        }
                    }
                } label: {
                    Label("Link an Adult", systemImage: "link")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(others.isEmpty)
                .help("Link the adult who will introduce \(youth.fullName) to their board, if they did not say so at sign-in")
            }
        }
    }
}
