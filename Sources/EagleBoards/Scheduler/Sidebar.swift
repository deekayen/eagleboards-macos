import EagleBoardsCore
import SwiftUI

/// The queue's filters (O-3): Waiting, On Boards and Finished youth, and the
/// adults. Choosing one only changes which list is shown beside the rooms;
/// the rooms and the inspector stay put, so a room's timer is never out of
/// sight while working the queue.
struct SchedulerSidebar: View {
    @Environment(AppModel.self) private var model
    let night: EventNight

    var body: some View {
        let selection = Binding<AppModel.Section?>(
            get: { model.section },
            set: { if let section = $0 { model.show(section) } }
        )

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
                DonateButton()
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
