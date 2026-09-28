import EagleBoardsCore
import SwiftUI

/// The main window's pages (SPEC.md P-6): Event, where boards are built and
/// run with every youth, the rooms and the inspector in view (O-3); Results,
/// every board and how it went; and People, the adults. Records stays a
/// window of its own.
struct SchedulerSidebar: View {
    @Environment(AppModel.self) private var model
    let night: EventNight

    var body: some View {
        let selection = Binding<AppModel.Page?>(
            get: { model.page },
            set: { if let page = $0 { model.show(page) } }
        )

        List(selection: selection) {
            Label("Event", systemImage: "person.3.sequence")
                .badge(model.waitingCount)
                .help("The youth, the rooms and the board being built. The number is how many youth are waiting.")
                .tag(AppModel.Page.event)
            Label("Results", systemImage: "checklist")
                .help("Every board and its result")
                .tag(AppModel.Page.results)
            Label("People", systemImage: "person.2")
                .badge(night.adults.filter(\.isAvailable).count)
                .help("Adults who signed in. The number is how many are free.")
                .tag(AppModel.Page.people)
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
}
