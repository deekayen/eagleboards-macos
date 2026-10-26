import EagleBoardsCore
import SwiftUI

/// One card per room: who is in it, and how long the board has been at it.
/// Drop a waiting youth on a free room to seat their board there.
///
/// The search finds a person's room (SPEC.md D-21): it narrows the cards to
/// the rooms holding someone whose name matches, youth or board member, and
/// any room named by it, and says above them where anyone it matched in no
/// room is. Return opens the first room found, or the youth found.
///
/// The cards are one focus section and take focus as a collection's items
/// do: the card with focus is the selected room, the arrow keys move through
/// the cards, and Return takes the room's next step, as a double click does.
struct RoomsGrid: View {
    @Environment(AppModel.self) private var model
    let event: BoardEvent
    @FocusState private var focusedRoomID: Room.ID?
    /// How many cards fit across, for Up and Down.
    @State private var columns = 1
    /// What the find last said to VoiceOver.
    @State private var findSaid = ""

    var body: some View {
        if event.rooms.isEmpty {
            NoRoomsYet(event: event)
        } else {
            let find = event.find(model.searchText)
            let rooms = find.rooms
            // Whom the narrowed cards hold, which only the cards show, then
            // the note: said once the typing pauses, and again only when it
            // changes, not on every sign-in at the door.
            let spoken = PersonFind.spoken(model.searchText, people: find.people, rooms: event.rooms)
            ScrollViewReader { scroller in
                ScrollView {
                    if let note = find.note {
                        Label(note, systemImage: "person.fill.questionmark")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.horizontal, .top], 12)
                            .accessibilityAddTraits(.updatesFrequently)
                            .accessibilityLabel(spoken)
                    }
                    TimelineView(.everyMinute) { timeline in
                        grid(rooms, now: timeline.date, scroller: scroller)
                    }
                }
                .onChange(of: focusedRoomID) { _, id in
                    guard let id else { return }
                    if id != model.selectedRoomID { model.selectRoom(id) }
                    scroller.scrollTo(id)
                }
                // A room selected another way (its youth, a drop, the
                // search) is where the arrow keys go on from.
                .onChange(of: model.selectedRoomID) { _, id in
                    if focusedRoomID != nil, let id, rooms.contains(where: { $0.id == id }) {
                        focusedRoomID = id
                    }
                }
                .task(id: spoken) {
                    guard (try? await Task.sleep(for: .milliseconds(500))) != nil, spoken != findSaid else { return }
                    findSaid = spoken
                    Speech.say(spoken)
                }
            }
        }
    }

    private func grid(_ rooms: [Room], now: Date, scroller: ScrollViewProxy) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cardWidth), spacing: Self.spacing)], spacing: Self.spacing) {
            ForEach(rooms) { room in
                RoomCard(room: room, event: event, now: now, isSelected: room.id == model.selectedRoomID)
                    // Focus shows as the selection, not a ring: a highlight
                    // in a collection, as in a list.
                    .focusable()
                    .focused($focusedRoomID, equals: room.id)
                    .focusEffectDisabled()
                    // A double click alongside the single one, not
                    // before it: an exclusive double click makes
                    // every single click wait to see if it is one.
                    .onTapGesture {
                        model.selectRoom(room.id)
                        focusedRoomID = room.id
                    }
                    .simultaneousGesture(TapGesture(count: 2).onEnded { model.performNextStep() })
                    .onKeyPress(.return) {
                        if model.selectedRoomID != room.id { model.selectRoom(room.id) }
                        model.performNextStep()
                        return .handled
                    }
                    .onMoveCommand { direction in
                        move(direction, from: room.id, in: rooms, scroller: scroller)
                    }
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
                    .contextMenu {
                        RoomActionButtons(model: model, event: event, roomID: room.id, inContextMenu: true)
                    }
                    .youthDropDestination(room: room)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rooms")
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width in
            columns = CardGrid.columns(width: width, minimum: Self.cardWidth, spacing: Self.spacing)
        }
        .focusSection()
        .padding(12)
    }

    private static let cardWidth = 220.0
    private static let spacing = 10.0

    /// An arrow key on a card: focus, and with it the selection, moves to
    /// the card beside, above or below it.
    private func move(_ direction: MoveCommandDirection, from roomID: Room.ID, in rooms: [Room], scroller: ScrollViewProxy) {
        let move: CardGrid.Move
        switch direction {
        case .left: move = .left
        case .right: move = .right
        case .up: move = .up
        case .down: move = .down
        @unknown default: return
        }
        guard let index = rooms.firstIndex(where: { $0.id == roomID }),
              let next = CardGrid.index(after: move, from: index, count: rooms.count, columns: columns)
        else { return }
        let id = rooms[next].id
        // Into view first: the grid is lazy, so a card out of sight may not
        // be built yet for focus to land on.
        scroller.scrollTo(id)
        focusedRoomID = id
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
                // A refused drop slides back, as the message says why.
                return model.seat(scoutID: scoutID, inRoom: room.id)
            } isTargeted: { isTargeted = $0 }
    }
}

struct RoomCard: View {
    let room: Room
    let event: BoardEvent
    let now: Date
    let isSelected: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.controlActiveState) private var activeState

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
                    Text(room.scoutName.shownValue).fontWeight(.semibold)
                    if let occupant {
                        StatusBadge(statusText: occupant.statusText)
                    }
                }
                // One member per line, in full, as on Windows: the cards are
                // where people look to find which room someone is in.
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(room.memberNames(occupant: occupant, among: event.adults).enumerated()), id: \.offset) { _, name in
                        Text(name)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        // One label, with the members named as members. Read child by
        // child, they were bare names after the status.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(room.spokenLabel(occupant: occupant, adults: event.adults, minutes: minutes, timer: timer))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The selection in gray while the window is not the key window, as a
    /// Mac list shows it.
    private var isEmphasized: Bool { activeState == .key }

    private var fill: Color {
        guard isSelected else { return Color(nsColor: .controlBackgroundColor) }
        return isEmphasized ? Color.accentColor.opacity(0.12) : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    /// An unselected card's edge: the separator color, or the label color
    /// under Increase Contrast, which asks for edges that stand out.
    private var border: Color {
        if isSelected { return isEmphasized ? Color.accentColor : Color.secondary }
        return contrast == .increased ? Color.primary : Color(nsColor: .separatorColor)
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
        case .okay: "\(Count.minutes(minutes)) since the last step"
        case .warning: "\(Count.minutes(minutes)): running long, past the time in Settings. Worth checking on."
        case .overdue: "\(Count.minutes(minutes)): overdue, past the time in Settings."
        }
    }

    private var spoken: String {
        switch state {
        case .okay: Count.minutes(minutes)
        case .warning: "\(Count.minutes(minutes)), running long"
        case .overdue: "\(Count.minutes(minutes)), overdue"
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
            Text("A board cannot be seated without a room. Mark each one Final Board or Proposal Review by what it is used for today.")
        } actions: {
            HStack {
                Button("Add Room…") { model.present(.addRoom) }
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
/// environment to read the model from. Dimmed, and still there, with no
/// event open, none before this one, or a page that shows no rooms.
struct CopyRoomsItems: View {
    let model: AppModel
    let event: BoardEvent?

    var body: some View {
        let earlierEvents = event.map { event in event.folder.events().filter { $0 < event.date } } ?? []
        Menu("Copy Rooms From") {
            ForEach(earlierEvents.prefix(12), id: \.self) { earlier in
                Button(Timestamp.shownDate(earlier)) { model.copyRooms(from: earlier) }
                    .help(earlier)
            }
        }
        .fixedSize()
        .disabled(earlierEvents.isEmpty || !model.page.showsRooms)
        .help("Add an earlier event's rooms, empty, except those already here")
    }
}

/// What can be done to a room: the Room menu, and the context menu on its
/// card or its row on the Rooms page. The Room menu always lists every item,
/// dimmed with no event open or on a page that shows no rooms
/// (`SchedulerPage.showsRooms`: the Event page's cards and the Rooms page's
/// table), where a room selected on the way is not the one in view. A room's
/// own menu lists only what applies to it; Add Room… and Copy Rooms From concern
/// no one room, so they stay in the Room menu.
struct RoomActionButtons: View {
    let model: AppModel
    let event: BoardEvent?
    /// Nil acts on the selected room.
    var roomID: Room.ID?
    var inContextMenu = false

    var body: some View {
        let inView = model.page.showsRooms
        let room = inView ? (roomID ?? model.selectedRoomID).flatMap { event?.room(id: $0) } : nil

        if !inContextMenu {
            Button("Add Room…") { model.present(.addRoom) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(event == nil || !inView)
            CopyRoomsItems(model: model, event: event)
            Divider()
        }
        MenuCommand("Rename…", applies: room != nil, inContextMenu: inContextMenu) {
            run(room) { model.present(.renameRoom(roomID: $0.id)) }
        }
        MenuCommand("Move Board to Another Room…", applies: room != nil, inContextMenu: inContextMenu) {
            run(room) { model.present(.swapRooms(roomID: $0.id)) }
        }
        if room != nil || !inContextMenu {
            Picker("Used For", selection: Binding(
                get: { room?.boardType },
                set: { newType in
                    if let room, let newType { model.setBoardType(newType, forRoom: room.id) }
                }
            )) {
                ForEach(BoardType.allCases) { Text($0.label).tag(Optional($0)) }
            }
            .disabled(room == nil)
        }
        if !inContextMenu || room?.isFree == true {
            Divider()
        }
        MenuCommand("Remove Room…", applies: room?.isFree == true, inContextMenu: inContextMenu) {
            run(room) { _ in model.removeSelectedRoom() }
        }
    }

    private func run(_ room: Room?, _ action: (Room) -> Void) {
        guard let room else { return }
        model.selectedRoomID = room.id
        action(room)
    }
}
