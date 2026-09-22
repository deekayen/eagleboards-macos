import AppKit
import EagleBoardsCore
import SwiftUI

@main
struct EagleBoardsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Eagle Boards", id: WindowID.scheduler) {
            SchedulerWindow()
                .environment(model)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1280, height: 860)
        .commands { EagleBoardsCommands(model: model) }

        Window("Records", id: WindowID.records) {
            RecordsWindow()
                .environment(model)
        }
        .defaultSize(width: 1100, height: 700)

        Window("Eagle Boards Help", id: WindowID.help) {
            HelpView()
        }
        .defaultSize(width: 720, height: 760)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

enum WindowID {
    static let scheduler = "scheduler"
    static let records = "records"
    static let help = "help"
}

/// Keeps the app a regular app when launched straight from `swift run`, and
/// asks before quitting while the sign-in station is serving.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isServing else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop the sign-in station and quit?"
        alert.informativeText = "The sign-in tablets will not be able to register anyone until Eagle Boards is open again. "
            + "Everything recorded so far is saved."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

struct EagleBoardsCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Another Night…") { model.sheet = .openNight }
                .keyboardShortcut("o")
                .disabled(model.dataFolder == nil)
            Button("Choose Data Folder…") { model.chooseDataFolderWithPanel() }
            Button("Show Tonight's Folder in Finder") { model.showDataFolderInFinder() }
                .disabled(model.night == nil)
            Divider()
            Button("Import Sign-Ups from SignUpGenius") { Task { await model.importSignUps() } }
                .keyboardShortcut("i")
                .disabled(model.night == nil || model.isImporting)
            Button("Export Board Results…") { model.exportReport() }
                .keyboardShortcut("e")
                .disabled(model.night == nil)
        }
        CommandGroup(before: .windowList) {
            Button("Scheduler") { openWindow(id: WindowID.scheduler) }
                .keyboardShortcut("1")
            Button("Records") { openWindow(id: WindowID.records) }
                .keyboardShortcut("2")
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Eagle Boards Help") { openWindow(id: WindowID.help) }
                .keyboardShortcut("?")
        }
    }
}
