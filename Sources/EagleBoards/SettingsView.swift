import EagleBoardsCore
import SwiftUI

struct SettingsView: View {
    /// The pane last shown, brought back when Settings opens again.
    @AppStorage("settingsPane") private var pane = "general"
    /// A failure in Settings is said here, over the Settings window. The
    /// scheduler's alerts would open behind it, or wait for that window.
    @State private var problem: AppModel.Message?

    var body: some View {
        TabView(selection: $pane) {
            GeneralSettings(problem: $problem)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            TimerSettings(problem: $problem)
                .tabItem { Label("Timers", systemImage: "timer") }
                .tag("timers")
            SignUpGeniusSettings(problem: $problem)
                .tabItem { Label("SignUpGenius", systemImage: "square.and.arrow.down") }
                .tag("signUpGenius")
        }
        .frame(width: 560)
        .alert(problem?.title ?? "", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }),
               presenting: problem) { _ in
            Button("OK", role: .cancel) {}
        } message: { problem in
            Text(problem.text)
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Binding var problem: AppModel.Message?
    @State private var portText = ""

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                Picker("When you select a waiting youth", selection: $model.proposeBoards) {
                    Text("Propose a board").tag(true)
                    Text("Start with an empty board").tag(false)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Boards")
            } footer: {
                Text("A proposed board picks a chair, members and a room with the whole waiting line in mind. "
                    + "Start empty to choose the adults yourself; a free room is still picked, and Start Over "
                    + "in the inspector proposes one whenever you want it.")
                    .foregroundStyle(.secondary)
            }
            Section("Data folder") {
                LabeledContent("Folder", value: model.dataFolder?.root.path ?? "Not chosen")
                HStack {
                    Button("Choose…") { model.chooseDataFolderWithPanel() }
                    Button("Show in Finder") { model.showDataFolderInFinder() }
                        .disabled(model.event == nil)
                }
            }
            Section {
                TextField("Port", text: $portText)
                    .onSubmit(applyPort)
                    .frame(maxWidth: 200)
                Button("Apply") { applyPort() }
                    .disabled(LaunchSettings.port(from: portText) == model.port)
            } header: {
                Text("Sign-in station")
            } footer: {
                Text("Tablets connect to this port, a number from \(Self.portRange). 8080 is the usual choice; "
                    + "change it only if another program already uses it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { portText = String(model.port) }
    }

    private static let portRange = "\(LaunchSettings.allowedPorts.lowerBound) to \(LaunchSettings.allowedPorts.upperBound)"

    /// A port that will not do is said, and left as typed to correct.
    private func applyPort() {
        guard let port = LaunchSettings.port(from: portText) else {
            let typed = portText.trimmingCharacters(in: .whitespaces)
            problem = AppModel.Message(
                title: "Choose a port from \(Self.portRange).",
                text: (typed.isEmpty ? "" : "“\(typed)” is not one. ") + "The sign-in station stays on port \(model.port).")
            return
        }
        model.port = port
    }
}

/// Room-card timers. They are guidance, not limits: the timers prompt
/// someone to check on the room, and nothing stops a board that needs longer.
private struct TimerSettings: View {
    @Environment(AppModel.self) private var model
    @Binding var problem: AppModel.Message?

    var body: some View {
        if let event = model.event {
            Form {
                Section {
                    minutes("Convening, overdue after", \.conveneRedMinutes, event)
                } header: {
                    Text("Board convening (Seat Board to Start Review)")
                } footer: {
                    Text("Guide to Advancement 8.0.3.0 #8: members convene at least 30 minutes before the board to go over the "
                        + "application, references and project workbook. Used here as a cap: past it the youth is being kept "
                        + "waiting. It is never just running long, because it is a limit rather than a target.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    minutes("Running long after", \.finalYellowMinutes, event)
                    minutes("Overdue after", \.finalRedMinutes, event)
                } header: {
                    Text("Final board review (from Start Review)")
                } footer: {
                    Text("Guide to Advancement 8.0.3.0 #9: Eagle boards generally last 30 minutes or somewhat longer, but "
                        + "rarely should one last longer than 45 minutes.")
                        .foregroundStyle(.secondary)
                    runningLongNote(\.finalYellowMinutes, \.finalRedMinutes, event)
                }
                Section {
                    minutes("Running long after", \.projectYellowMinutes, event)
                    minutes("Overdue after", \.projectRedMinutes, event)
                } header: {
                    Text("Proposal review (from Start Review)")
                } footer: {
                    Text("District practice. A proposal review is not a board of review, so the Guide sets no length for it.")
                        .foregroundStyle(.secondary)
                    runningLongNote(\.projectYellowMinutes, \.projectRedMinutes, event)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Open an event first", systemImage: "timer")
                .frame(height: 200)
        }
    }

    /// Said rather than prevented: a Running long stepper bounded by Overdue
    /// would still be left past it whenever Overdue is lowered.
    @ViewBuilder
    private func runningLongNote(_ yellow: KeyPath<Config, Int>, _ red: KeyPath<Config, Int>, _ event: BoardEvent) -> some View {
        let runningLong = event.config[keyPath: yellow]
        let overdue = event.config[keyPath: red]
        if runningLong > 0, overdue > 0, runningLong >= overdue {
            NoticeLabel.warning("Running long is at or past Overdue, so these reviews go from on time straight to overdue.")
                .foregroundStyle(.secondary)
        }
    }

    private func minutes(_ label: String, _ keyPath: WritableKeyPath<Config, Int>, _ event: BoardEvent) -> some View {
        Stepper(value: configBinding(keyPath, event), in: 0...240) {
            LabeledContent(label, value: event.config[keyPath: keyPath] == 0 ? "off" : "\(event.config[keyPath: keyPath]) min")
        }
    }

    private func configBinding(_ keyPath: WritableKeyPath<Config, Int>, _ event: BoardEvent) -> Binding<Int> {
        Binding(
            get: { event.config[keyPath: keyPath] },
            set: { newValue in
                var edited = event.config
                edited[keyPath: keyPath] = newValue
                do {
                    try event.updateConfig(edited)
                } catch {
                    problem = AppModel.Message(title: "Could Not Save the Timers", text: error.localizedDescription)
                }
            }
        )
    }
}

private struct SignUpGeniusSettings: View {
    @Environment(AppModel.self) private var model
    @Binding var problem: AppModel.Message?
    @State private var key = ""
    @State private var saved = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                SecureField("API key", text: $key)
                HStack {
                    Button("Save Key") {
                        saved = model.saveSignUpGeniusKey(key)
                        if !saved {
                            problem = AppModel.Message(
                                title: "Could Not Save the Key in Your Keychain",
                                text: "macOS would not store the SignUpGenius key. "
                                    + (model.hasSignUpGeniusKey
                                        ? "The key saved before is still there."
                                        : "No key is saved now, so sign-ups cannot be imported until one is.")
                                    + " Try Save Key again.")
                        }
                    }
                    .disabled(!model.signUpGeniusAllowed)
                    if saved {
                        NoticeLabel("Saved in your keychain", systemImage: "checkmark.circle.fill", tint: .green)
                    }
                }
            } header: {
                Text("SignUpGenius")
            } footer: {
                Text("With a key, Eagle Boards reads today's Eagle board sign-up: youth become pre-registrations, so their "
                    + "details fill in at the door and they sign in as P rather than W, and adults are added to the history. "
                    + "The key is kept in your macOS keychain, not in the data folder.")
                    .foregroundStyle(.secondary)
                if !model.signUpGeniusAllowed {
                    NoticeLabel.warning("Off for this run: EAGLEBOARDS_DATA_FOLDER is set, so the keychain is not read. "
                        + "Set EAGLEBOARDS_SIGNUPGENIUS=1 to use it with a scratch folder.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Import when today's event is opened", isOn: $model.importOnOpen)
                HStack {
                    // The import reports in the scheduler window, so it comes
                    // forward to show it.
                    Button("Import Now") {
                        model.openScheduler()
                        Task { await model.importSignUps() }
                    }
                    .disabled(model.event == nil || model.isImporting || !model.hasSignUpGeniusKey)
                    if model.isImporting {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Importing sign-ups from SignUpGenius")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Shown masked; read once when the tab opens so it can be edited.
            if model.hasSignUpGeniusKey {
                key = SignUpGeniusKeychain.read() ?? ""
            }
        }
        .onChange(of: key) { saved = false }
    }
}
