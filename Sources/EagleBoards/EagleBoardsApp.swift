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

        Window("Sign-In Code", id: WindowID.signInCode) {
            SignInCodeWindow()
                .environment(model)
        }
        .defaultSize(width: 560, height: 680)

        Window("Eagle Boards Help", id: WindowID.help) {
            HelpView()
        }
        .defaultSize(width: 720, height: 760)

        Window("Donate", id: WindowID.donate) {
            DonateView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

enum WindowID {
    static let scheduler = "scheduler"
    static let help = "help"
    static let signInCode = "signInCode"
    static let donate = "donate"
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
            Button("Open Another Event…") { model.sheet = .openNight }
                .keyboardShortcut("o")
                .disabled(model.dataFolder == nil)
            Menu("Open Recent Event") {
                ForEach(recentNights, id: \.self) { name in
                    Button(name == model.today ? "\(name) (Today)" : name) {
                        if let folder = model.dataFolder { model.open(folder: folder, night: name) }
                    }
                    .disabled(name == model.night?.night)
                }
            }
            .disabled(recentNights.isEmpty)
            Button("Choose Data Folder…") { model.chooseDataFolderWithPanel() }
            Button("Show Event Folder in Finder") { model.showDataFolderInFinder() }
                .disabled(model.night == nil)
            Divider()
            Button("Import Sign-Ups from SignUpGenius") { Task { await model.importSignUps() } }
                .keyboardShortcut("i")
                .disabled(model.night == nil || model.isImporting)
            Button("Export Board Results…") { model.exportReport() }
                .keyboardShortcut("e")
                .disabled(model.night == nil)
            Button("Export List…") { model.exportList() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.night == nil || !model.page.isList)
        }
        InspectorCommands()
        // The pages (SPEC.md P-1, P-6): the event, and its records, each a
        // list edited in place. No sidebar chooses them and no records window
        // repeats them; the page shown has a check.
        CommandGroup(before: .toolbar) {
            ForEach(Array(AppModel.Page.allCases.enumerated()), id: \.element) { index, page in
                pageButton(page, KeyEquivalent(Character(String(index + 1))))
            }
        }
        CommandMenu("Board") {
            YouthActionButtons(model: model)
                .disabled(model.night == nil)
        }
        CommandMenu("Adult") {
            Button("Add Adult…") { model.sheet = .addAdult }
                .disabled(model.night == nil || model.sheet != nil)
            Divider()
            AdultActionButtons(model: model)
                .disabled(model.night == nil)
        }
        CommandMenu("Room") {
            if let night = model.night {
                RoomActionButtons(model: model, night: night)
            } else {
                Button("Add Room…") {}
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(true)
            }
        }
        CommandGroup(before: .windowList) {
            Button("Scheduler") { openWindow(id: WindowID.scheduler) }
                .keyboardShortcut("1")
            Button("Sign-In Code") { openWindow(id: WindowID.signInCode) }
                .keyboardShortcut("3")
            Divider()
        }
        CommandGroup(replacing: .appInfo) {
            Button("About Eagle Boards") { AboutPanel.show() }
        }
        CommandGroup(replacing: .help) {
            Button("Eagle Boards Help") { openWindow(id: WindowID.help) }
                .keyboardShortcut("?")
            Divider()
            // SPEC.md D-17: the one Donate link, with a heart.
            Button {
                openWindow(id: WindowID.donate)
            } label: {
                Label("Donate…", systemImage: "heart")
            }
        }
    }

    /// The nights on file, newest first, and tonight even before it has a folder.
    private var recentNights: [String] {
        guard let folder = model.dataFolder else { return [] }
        let onFile = folder.nights().sorted(by: >)
        let nights = onFile.contains(model.today) ? onFile : [model.today] + onFile
        return Array(nights.prefix(10))
    }

    private func pageButton(_ page: AppModel.Page, _ key: KeyEquivalent) -> some View {
        Toggle(page.title, isOn: Binding(
            get: { model.night != nil && model.page == page },
            set: { _ in
                openWindow(id: WindowID.scheduler)
                model.show(page)
            }
        ))
        .keyboardShortcut(key, modifiers: [.command, .option])
        .disabled(model.night == nil)
    }
}
