import EagleBoardsCore
import SwiftUI

/// One card per room: who is in it, and how long the board has been at it.
/// Drop a waiting youth on a free room to seat their board there.
///
/// The search finds a person's room (SPEC.md D-21): it narrows the cards to
/// the rooms holding someone whose name matches, youth or board member, and
/// any room named by it, and says above them where anyone it matched in no
/// room is. Return opens the first room found, or the youth found.
struct RoomsGrid: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent

    var body: some View {
        if event.rooms.isEmpty {
            NoRoomsYet(event: event)
        } else {
            let find = event.find(model.searchText)
            let rooms = find.rooms
            ScrollView {
                if let note = find.note {
                    Label(note, systemImage: "person.fill.questionmark")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top], 12)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                TimelineView(.periodic(from: .now, by: 20)) { timeline in
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(rooms) { room in
                            RoomCard(room: room, event: event, now: timeline.date, isSelected: room.id == model.selectedRoomID)
                                // A double click alongside the single one, not
                                // before it: an exclusive double click makes
                                // every single click wait to see if it is one.
                                .onTapGesture { model.selectRoom(room.id) }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { model.performNextStep() })
                                // The same through VoiceOver: pressing the card
                                // selects it, and its board's next step is an
                                // action, as a double click would take it.
                                .accessibilityAction { model.selectRoom(room.id) }
                                .accessibilityActions {
                                    if let step = event.occupant(of: room)?.status?.nextStep {
                                        Button(step.title) {
                                            model.selectRoom(room.id)
                                            model.performNextStep()
                                        }
                                    }
                                }
                                .contextMenu { RoomActionButtons(model: model, event: event, roomID: room.id) }
                                .youthDropDestination(room: room)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

extension BoardEvent {
    /// A find over the room cards (SPEC.md D-21): the rooms to show, in the
    /// cards' order; who it found; and what to say about those in no room.
    func find(_ query: String) -> (rooms: [Room], people: [PersonPlace], note: String?) {
        let people = PersonFind.people(query, youth: scouts, adults: adults)
        let shown = PersonFind.rooms(query, people: people, rooms: rooms)
        return (
            shown.map { names in rooms.filter { names.contains($0.name) } } ?? rooms,
            people,
            PersonFind.note(people: people, roomsFound: shown)
        )
    }
}

extension BoardEvent {
    /// The youth whose board is in this room right now.
    func occupant(of room: Room) -> Scout? {
        guard !room.isFree else { return nil }
        return scouts.first { $0.room == room.name && ($0.status == .seated || $0.status == .inProgress) }
    }
}

extension View {
    /// Seat a waiting youth dropped here in this room. The room shows it will
    /// take them while they hover, if it is free.
    func youthDropDestination(room: Room) -> some View {
        modifier(YouthDropTarget(room: room))
    }
}

private struct YouthDropTarget: ViewModifier {
    @Environment(AppModel.self) private var model
    let room: Room
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted && room.isFree {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let scoutID = DragPayload.youthIDs(in: items).first else { return false }
                model.seat(scoutID: scoutID, inRoom: room.id)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

struct RoomCard: View {
    let room: Room
    let event: BoardEvent
    let now: Date
    let isSelected: Bool

    var body: some View {
        let occupant = event.occupant(of: room)
        let minutes = occupant?.minutesSinceLastUpdate(now: now)
        let timer = occupant.flatMap { youth in
            minutes.flatMap { RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: $0, config: event.config) }
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Room \(room.name)").font(.headline)
                Text(room.boardType?.label ?? room.boardTypeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let minutes, let timer {
                    TimerBadge(minutes: minutes, state: timer)
                }
            }
            if room.isFree {
                Text("Free").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Text(room.scoutName).fontWeight(.semibold)
                    if let occupant {
                        StatusBadge(statusText: occupant.statusText)
                    }
                }
                // One member per line, in full, as on Windows: the cards are
                // where people look to find which room someone is in.
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(room.leaderNames.memberLines.enumerated()), id: \.offset) { _, name in
                        Text(name)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Minutes since the board's last step, with a clock per state (SPEC.md
/// D-13): a stopwatch on time, a timer on the orange tint running long, an
/// alarm clock on the solid fill overdue, at the limits set in Settings. The
/// three differ in outline and the last two in lightness, so the state reads
/// with color blindness; VoiceOver says it in words.
struct TimerBadge: View {
    let minutes: Int
    let state: RoomTimer.State
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text("\(minutes)m").monospacedDigit()
        }
        .font(.callout.weight(state == .okay ? .regular : .bold))
        .foregroundStyle(foreground)
        .padding(.horizontal, fill == nil ? 0 : 5)
        .background {
            if let fill {
                Capsule().fill(fill)
            }
        }
        .overlay {
            if fill != nil && contrast == .increased {
                Capsule().strokeBorder(foreground)
            }
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var symbol: String {
        switch state {
        case .okay: "stopwatch"
        case .warning: "timer"
        case .overdue: "alarm"
        }
    }

    private var foreground: Color {
        switch state {
        case .okay: .secondary
        case .warning: StatusPalette.long.foreground
        case .overdue: StatusPalette.overdue.foreground
        }
    }

    private var fill: Color? {
        switch state {
        case .okay: nil
        case .warning: StatusPalette.long.background
        case .overdue: StatusPalette.overdue.background
        }
    }

    private var help: String {
        switch state {
        case .okay: "\(minutes) minutes since the last step"
        case .warning: "\(minutes) minutes: running long, past the time in Settings. Worth checking on."
        case .overdue: "\(minutes) minutes: overdue, past the time in Settings."
        }
    }

    private var spoken: String {
        switch state {
        case .okay: "\(minutes) minutes"
        case .warning: "\(minutes) minutes, running long"
        case .overdue: "\(minutes) minutes, overdue"
        }
    }
}

/// Shown until the first room is added, offering last month's list.
struct NoRoomsYet: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent

    var body: some View {
        let earlierEvents = event.folder.events().filter { $0 < event.date }
        ContentUnavailableView {
            Label("No Rooms Yet", systemImage: "door.left.hand.closed")
        } description: {
            Text("A board cannot be seated without a room. Mark each one Final or Project by what it is used for today.")
        } actions: {
            HStack {
                Button("Add Room…") { model.sheet = .addRoom }
                if !earlierEvents.isEmpty {
                    CopyRoomsMenu(event: event)
                }
            }
        }
    }
}

/// Add an earlier event's rooms, empty. Rooms this event already has are skipped.
struct CopyRoomsMenu: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent

    var body: some View {
        CopyRoomsItems(model: model, event: event)
    }
}

/// The Copy Rooms From menu, usable in the menu bar where there is no
/// environment to read the model from.
struct CopyRoomsItems: View {
    let model: AppModel
    let event: BoardEvent

    var body: some View {
        let earlierEvents = event.folder.events().filter { $0 < event.date }
        Menu("Copy Rooms From") {
            ForEach(earlierEvents.prefix(12), id: \.self) { earlier in
                Button(earlier) {
                    model.attempt("Could not copy the rooms") { _ = try event.copyRooms(fromEvent: earlier) }
                }
            }
        }
        .fixedSize()
        .disabled(earlierEvents.isEmpty)
        .help("Add the rooms from an earlier event, empty. Rooms already here are skipped.")
    }
}

/// What can be done to a room: the Room menu, and the context menu on its
/// card.
struct RoomActionButtons: View {
    let model: AppModel
    let event: BoardEvent
    /// Nil acts on the selected room.
    var roomID: Room.ID?

    var body: some View {
        let room = (roomID ?? model.selectedRoomID).flatMap { event.room(id: $0) }

        Button("Add Room…") { model.sheet = .addRoom }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        CopyRoomsItems(model: model, event: event)
        Divider()
        Button("Rename…") { run(room) { model.sheet = .renameRoom(roomID: $0.id) } }
            .disabled(room == nil)
        Button("Move Board to Another Room…") { run(room) { model.sheet = .swapRooms(roomID: $0.id) } }
            .disabled(room == nil)
        Picker("Used For", selection: Binding(
            get: { room?.boardType },
            set: { newType in
                if let room, let newType { model.setBoardType(newType, forRoom: room.id) }
            }
        )) {
            ForEach(BoardType.allCases) { Text($0.label).tag(Optional($0)) }
        }
        .disabled(room == nil)
        Divider()
        Button("Remove Room") { run(room) { _ in model.removeSelectedRoom() } }
            .disabled(room?.isFree != true)
    }

    private func run(_ room: Room?, _ action: (Room) -> Void) {
        guard let room else { return }
        model.selectedRoomID = room.id
        action(room)
    }
}
