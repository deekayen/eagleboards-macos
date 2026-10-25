import EagleBoardsCore
import SwiftUI

/// The main window: the welcome screen until there is a data folder, then the
/// scheduler for the open event.
struct SchedulerWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let event = model.event {
                SchedulerView(event: event)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        // For the model's commands, which can run with this window closed.
        .onAppear { model.openWindow = { [openWindow] id in openWindow(id: id) } }
        .background(WindowReader { [weak model] in model?.schedulerWindow = $0 })
    }
}

/// Hands over the AppKit window it is drawn in, for the save and open
/// panels, which SwiftUI cannot attach to a window itself.
private struct WindowReader: NSViewRepresentable {
    let found: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView(found: found) }
    func updateNSView(_ view: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        let found: @MainActor (NSWindow) -> Void

        init(found: @escaping @MainActor (NSWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            // Decoration above the title, which says it.
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Eagle Boards")
                .font(.largeTitle.bold())
                .heading(.h1)
            Text("Check youth and adults in on a tablet at the door, seat each board, and record the results.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Where should Eagle Boards keep its data?")
                        .font(.headline)
                    Text("Each event gets its own dated folder inside, and a history of every adult who has signed in is kept across events. "
                        + "It holds personal information, some of it about minors, so choose a private place.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Moving from the Java Eagle Board Scheduler? Choose the folder it ran in, the one holding "
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
                SheetProblem(text: error)
                    .textSelection(.enabled)
                    .frame(maxWidth: 560)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
