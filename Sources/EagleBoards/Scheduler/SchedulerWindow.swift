import EagleBoardsCore
import SwiftUI

/// The main window: the welcome screen until there is a data folder, then the
/// scheduler for the open night.
struct SchedulerWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let night = model.night {
                SchedulerView(night: night)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Eagle Boards")
                .font(.largeTitle.bold())
            Text("Check youth and adults in on a tablet at the door, seat each board, and record the results.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Where should Eagle Boards keep its data?")
                        .font(.headline)
                    Text("Each event night gets its own folder inside, and a history of every adult who has signed in is kept across nights. "
                        + "It holds personal information, some of it about minors, so choose a private place.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Moving from the Java Eagle Board Scheduler? Choose the folder it ran in -- the one holding "
                        + "Master_AdultHistory.csv and the dated folders. Both programs read the same files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Use Documents › Eagle Boards") { model.useDefaultDataFolder() }
                            .keyboardShortcut(.defaultAction)
                        Button("Choose Another Folder…") { model.chooseDataFolderWithPanel() }
                    }
                    .padding(.top, 4)
                }
                .padding(8)
            }
            .frame(maxWidth: 560)

            if let error = model.openError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .frame(maxWidth: 560)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
