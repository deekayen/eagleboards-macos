import EagleBoardsCore
import SwiftUI

/// The lists of the evening, with how many are in each, and every room with
/// its board and timer. Drop a waiting youth on a free room to seat them.
struct SchedulerSidebar: View {
    @Environment(AppModel.self) private var model
    let night: EventNight

    var body: some View {
        let selection = Binding<AppModel.Section?>(
            get: { model.section },
            set: { if let section = $0 { model.show(section) } }
        )

        TimelineView(.periodic(from: .now, by: 20)) { timeline in
            List(selection: selection) {
                Section("Youth") {
                    row("Waiting", "person.crop.circle.badge.clock", .waiting)
                    row("On Boards", "person.3", .onBoards)
                    row("Finished", "checkmark.circle", .finished)
                }
                Section("People") {
                    Label("Adults", systemImage: "person.2")
                        .badge(night.adults.filter(\.isAvailable).count)
                        .help("Adults who signed in. The number is how many are free.")
                        .tag(AppModel.Section.adults)
                }
                Section("Rooms") {
                    Label("All Rooms", systemImage: "square.grid.2x2")
                        .badge(Text("\(night.rooms.filter(\.isFree).count) free"))
                        .tag(AppModel.Section.rooms)
                    ForEach(night.rooms) { room in
                        RoomSidebarRow(room: room, night: night, now: timeline.date)
                            .tag(AppModel.Section.room(room.id))
                            .contextMenu { RoomActionButtons(model: model, night: night, roomID: room.id) }
                            .youthDropDestination(room: room)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    model.sheet = .addRoom
                } label: {
                    Label("Add Room", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a room for today")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func row(_ title: String, _ symbol: String, _ section: AppModel.Section) -> some View {
        Label(title, systemImage: symbol)
            .badge(night.scouts.filter(section.lists).count)
            .tag(section)
    }
}

/// A room in the sidebar: its name, what it is used for, and who is in it,
/// with the timer once it passes the yellow time.
private struct RoomSidebarRow: View {
    let room: Room
    let night: EventNight
    let now: Date

    var body: some View {
        let occupant = room.isFree ? nil : night.scouts.first {
            $0.room == room.name && ($0.status == .seated || $0.status == .inProgress)
        }
        let minutes = occupant?.minutesSinceLastUpdate(now: now)
        let timer = occupant.flatMap { youth in
            minutes.flatMap { RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: $0, config: night.config) }
        }

        HStack(spacing: 6) {
            Image(systemName: room.isFree ? "door.left.hand.open" : "door.left.hand.closed")
                .foregroundStyle(room.isFree ? .secondary : .primary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(room.name)
                    Text(room.boardType == .projectReview ? "Project" : room.boardTypeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(room.isFree ? "Free" : room.scoutName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let minutes, let timer, timer != .okay {
                TimerBadge(minutes: minutes, state: timer)
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
