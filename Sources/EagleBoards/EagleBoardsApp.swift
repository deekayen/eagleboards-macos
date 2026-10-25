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

        // Each Window scene would also list itself in the Window menu. The
        // menu's own Sign-In Code item (Command-3) is the one entry for that
        // window, and the Help menu opens Help and Donate.
        Window("Sign-In Code", id: WindowID.signInCode) {
            SignInCodeWindow()
                .environment(model)
        }
        .defaultSize(width: 560, height: 680)
        .commandsRemoved()

        Window("Eagle Boards Help", id: WindowID.help) {
            HelpView()
        }
        .defaultSize(width: 720, height: 760)
        .commandsRemoved()

        Window("Donate", id: WindowID.donate) {
            DonateView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

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
        // EAGLEBOARDS_APPEARANCE, for a screenshot run; otherwise the system's.
        switch LaunchSettings(environment: ProcessInfo.processInfo.environment, defaults: .standard).appearance {
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case nil: break
        }
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
            Button("Open Another Event…") { model.sheet = .openEvent }
                .keyboardShortcut("o")
                .disabled(model.dataFolder == nil)
            Menu("Open Recent Event") {
                ForEach(recentEvents, id: \.self) { name in
                    Button(name == model.today ? "\(name) (Today)" : name) {
                        if let folder = model.dataFolder { model.open(folder: folder, event: name) }
                    }
                    .disabled(name == model.event?.date)
                }
            }
            .disabled(recentEvents.isEmpty)
            Button("Choose Data Folder…") { model.chooseDataFolderWithPanel() }
            Button("Show Event Folder in Finder") { model.showDataFolderInFinder() }
                .disabled(model.event == nil)
        }
        // Below Close, where a Mac app keeps import and export.
        CommandGroup(after: .importExport) {
            Button("Import Sign-Ups from SignUpGenius") { Task { await model.importSignUps() } }
                .keyboardShortcut("i")
                .disabled(model.event == nil || model.isImporting)
            Button("Export Board Results…") { model.exportReport() }
                .keyboardShortcut("e")
                .disabled(model.event == nil)
            Button("Export List…") { model.exportList() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.event == nil || !model.page.isList)
            Divider()
            // The toolbar popover's commands, for when the toolbar is hidden.
            Button("Restart Sign-In Station") { model.startServer() }
                .disabled(model.event == nil || !model.serverFailed)
            Button("Open Sign-In Page in Browser") {
                if let url = model.localSignInURL { NSWorkspace.shared.open(url) }
            }
            .disabled(model.localSignInURL == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find…") {
                openWindow(id: WindowID.scheduler)
                model.findRequested = true
            }
            .keyboardShortcut("f")
            .disabled(model.event == nil)
        }
        InspectorCommands()
        // The pages (SPEC.md P-1, P-6): the event, then a page per table,
        // edited in place. No sidebar chooses them and no records window
        // repeats them; the page shown has a check.
        CommandGroup(before: .toolbar) {
            let pages = Array(AppModel.Page.allCases.enumerated())
            ForEach(pages.prefix(1), id: \.element) { index, page in
                pageButton(page, KeyEquivalent(Character(String(index + 1))))
            }
            Divider()
            ForEach(pages.dropFirst(), id: \.element) { index, page in
                pageButton(page, KeyEquivalent(Character(String(index + 1))))
            }
        }
        CommandMenu("Board") {
            YouthActionButtons(model: model)
                .disabled(model.event == nil)
        }
        CommandMenu("Adult") {
            Button("Add Adult…") { model.sheet = .addAdult }
                .keyboardShortcut("n")
                .disabled(model.event == nil || model.sheet != nil)
            Divider()
            AdultActionButtons(model: model)
                .disabled(model.event == nil)
        }
        CommandMenu("Room") {
            RoomActionButtons(model: model, event: model.event)
        }
        // In place of the scheduler scene's own Window menu entry, which
        // named it after the app. Replacing this group leaves the other
        // scenes' entries, so those scenes have commandsRemoved().
        CommandGroup(replacing: .singleWindowList) {
            Button("Scheduler") { openWindow(id: WindowID.scheduler) }
                .keyboardShortcut("1")
            Button("Sign-In Code") { openWindow(id: WindowID.signInCode) }
                .keyboardShortcut("3")
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

    /// The events on file, newest first, and today's even before it has a folder.
    private var recentEvents: [String] {
        guard let folder = model.dataFolder else { return [] }
        let onFile = folder.events().sorted(by: >)
        let events = onFile.contains(model.today) ? onFile : [model.today] + onFile
        return Array(events.prefix(10))
    }

    private func pageButton(_ page: AppModel.Page, _ key: KeyEquivalent) -> some View {
        Toggle(page.title, isOn: Binding(
            get: { model.event != nil && model.page == page },
            set: { _ in
                openWindow(id: WindowID.scheduler)
                model.show(page)
            }
        ))
        .keyboardShortcut(key, modifiers: [.command, .option])
        .disabled(model.event == nil)
    }
}
