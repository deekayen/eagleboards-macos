import EagleBoardsCore
import SwiftUI

/// One card per room: who is in it, and how long the board has been at it.
struct RoomsPanel: View {
    @Environment(AppModel.self) private var model
    let night: EventNight

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            PanelHeader(title: "Rooms", detail: "\(night.rooms.filter(\.isFree).count) of \(night.rooms.count) free") {
                TextField("Filter by room or name", text: $model.roomFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                Button {
                    model.sheet = .addRoom
                } label: {
                    Label("Add Room", systemImage: "plus")
                }
                .help("Add a room for tonight")
                Button {
                    model.confirmRemoveSelectedRoom()
                } label: {
                    Label("Remove Room", systemImage: "minus")
                }
                .disabled(model.selectedRoom == nil)
                .help("Remove the selected room")
                Button("Rename…") {
                    if let id = model.selectedRoomID { model.sheet = .renameRoom(roomID: id) }
                }
                .disabled(model.selectedRoom == nil)
                .help("Rename the selected room; a board in it moves with it")
                Button("Swap…") {
                    if let id = model.selectedRoomID { model.sheet = .swapRooms(roomID: id) }
                }
                .disabled(model.selectedRoom == nil)
                .help("Move the selected room's board to another room, or swap two boards")
                CopyRoomsMenu(night: night)
            }
            .labelStyle(.iconOnly)

            if night.rooms.isEmpty {
                NoRoomsYet(night: night)
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 20)) { timeline in
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                            ForEach(visibleRooms) { room in
                                RoomCard(room: room, night: night, now: timeline.date, isSelected: room.id == model.selectedRoomID)
                                    .onTapGesture { model.selectRoom(room.id) }
                                    .contextMenu {
                                        Button("Rename…") { model.sheet = .renameRoom(roomID: room.id) }
                                    }
                            }
                        }
                        .padding(8)
                    }
                }
            }
        }
    }

    private var visibleRooms: [Room] {
        let filter = model.roomFilter.trimmingCharacters(in: .whitespaces)
        guard !filter.isEmpty else { return night.rooms }
        return night.rooms.filter {
            $0.name.localizedCaseInsensitiveContains(filter)
                || $0.scoutName.localizedCaseInsensitiveContains(filter)
                || $0.leaderNames.localizedCaseInsensitiveContains(filter)
        }
    }
}

struct RoomCard: View {
    let room: Room
    let night: EventNight
    let now: Date
    let isSelected: Bool

    /// The youth whose board is in this room right now.
    private var occupant: Scout? {
        guard !room.isFree else { return nil }
        return night.scouts.first { $0.room == room.name && ($0.status == .seated || $0.status == .inProgress) }
    }

    var body: some View {
        let occupant = occupant
        let minutes = occupant?.minutesSinceLastUpdate(now: now)
        let timer = occupant.flatMap { youth in
            minutes.flatMap { RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: $0, config: night.config) }
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
                        StatusBadge(statusText: occupant.statusText, config: night.config)
                    }
                }
                Text(room.leaderNames.withListSeparators)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Minutes since the board's last step, turning yellow then red at the
/// limits set in Settings.
struct TimerBadge: View {
    let minutes: Int
    let state: RoomTimer.State

    var body: some View {
        HStack(spacing: 3) {
            if state != .okay {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            Text("\(minutes)m").monospacedDigit()
        }
        .font(.callout.weight(state == .okay ? .regular : .bold))
        .foregroundStyle(color)
        .help(help)
    }

    private var color: Color {
        switch state {
        case .okay: .secondary
        case .warning: .orange
        case .overdue: .red
        }
    }

    private var help: String {
        switch state {
        case .okay: "\(minutes) minutes since the last step"
        case .warning: "\(minutes) minutes: past the yellow time. Worth checking on."
        case .overdue: "\(minutes) minutes: past the red time."
        }
    }
}

/// Shown until the first room is added, offering last month's list.
struct NoRoomsYet: View {
    @Environment(AppModel.self) private var model
    let night: EventNight

    var body: some View {
        let earlierNights = night.folder.nights().filter { $0 < night.night }
        VStack(spacing: 8) {
            Text("No rooms yet").font(.headline)
            Text("A board cannot be seated without a room. Mark each one Final or Project by what it is used for tonight.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Add Room…") { model.sheet = .addRoom }
                if !earlierNights.isEmpty {
                    CopyRoomsMenu(night: night)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Add an earlier night's rooms, empty. Rooms tonight already has are skipped.
struct CopyRoomsMenu: View {
    @Environment(AppModel.self) private var model
    let night: EventNight

    var body: some View {
        let earlierNights = night.folder.nights().filter { $0 < night.night }
        Menu("Copy Rooms From") {
            ForEach(earlierNights.prefix(12), id: \.self) { earlier in
                Button(earlier) {
                    model.attempt { try night.copyRooms(fromNight: earlier) }
                }
            }
        }
        .fixedSize()
        .disabled(earlierNights.isEmpty)
        .help("Add the rooms from an earlier night, empty. Rooms already here are skipped.")
    }
}
