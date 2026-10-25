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
                // The Dock menu reaches the model through the delegate, also
                // when this window is the only one open.
                .onAppear { appDelegate.model = model }
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

/// Keeps the app a regular app when launched straight from `swift run`, asks
/// before quitting while the sign-in station is serving, and gives the Dock
/// icon a menu for the windows an operator reaches for once they are closed.
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

    /// Scheduler and Sign-In Code, as in the Window menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("Scheduler", #selector(showScheduler)), ("Sign-In Code", #selector(showSignInCode))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func showScheduler() { show(WindowID.scheduler) }
    @objc private func showSignInCode() { show(WindowID.signInCode) }

    private func show(_ windowID: String) {
        NSApplication.shared.activate()
        model?.openWindow?(windowID)
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
    /// Set while the Help window is in front.
    @FocusedValue(\.helpSearch) private var helpSearch

    var body: some Commands {
        CommandGroup(after: .newItem) {
            // Opening another event while a sheet is up would take the event
            // out from under it.
            Button("Open Another Event…") { model.present(.openEvent) }
                .keyboardShortcut("o")
                .disabled(model.dataFolder == nil || model.sheet != nil)
            Menu("Open Recent Event") {
                ForEach(recentEvents, id: \.self) { name in
                    // In the scheduler window, where the event shows, or the
                    // alert saying why it could not be opened.
                    Button(DataFolder.eventLabel(name, today: model.today)) {
                        guard let folder = model.dataFolder else { return }
                        model.openScheduler()
                        model.open(folder: folder, event: name)
                    }
                    .disabled(name == model.event?.date)
                }
            }
            .disabled(recentEvents.isEmpty || model.sheet != nil)
            Button("Choose Data Folder…") { model.chooseDataFolderWithPanel() }
                .disabled(model.sheet != nil)
            Button("Show Event Folder in Finder") { model.showDataFolderInFinder() }
                .disabled(model.event == nil)
        }
        // Below Close, where a Mac app keeps import and export.
        CommandGroup(after: .importExport) {
            Button(model.isImporting ? "Importing Sign-Ups…" : "Import Sign-Ups from SignUpGenius") {
                Task { await model.importSignUps() }
            }
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
            // The search of the window in front: Help's own, or else the
            // scheduler's, which comes forward for it.
            Button("Find…") {
                if let helpSearch {
                    helpSearch.start()
                } else {
                    openWindow(id: WindowID.scheduler)
                    model.findRequested = true
                }
            }
            .keyboardShortcut("f")
            .disabled(helpSearch == nil && model.event == nil)
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
        // Xcode 26's CommandsBuilder takes at most ten items in a block, and
        // CI builds with it, so the menus below are grouped to stay under that.
        Group {
            CommandMenu("Board") {
                YouthActionButtons(model: model)
                    .disabled(model.event == nil)
            }
            CommandMenu("Adult") {
                Button("Add Adult…") { model.present(.addAdult) }
                    .keyboardShortcut("n")
                    .disabled(model.event == nil || model.sheet != nil)
                Button("Sign In for Today") { model.signInFromHistory(model.historySelectionToSignIn) }
                    .disabled(model.historySelectionToSignIn.isEmpty)
                Divider()
                AdultActionButtons(model: model)
                    .disabled(model.event == nil)
            }
            // A room changed under an open sheet would change the board it is
            // drawing up, or replace the sheet with its own.
            CommandMenu("Room") {
                RoomActionButtons(model: model, event: model.event)
                    .disabled(model.sheet != nil)
            }
        }
        Group {
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
