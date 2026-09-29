import EagleBoardsCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            TimerSettings()
                .tabItem { Label("Timers", systemImage: "timer") }
            SignUpGeniusSettings()
                .tabItem { Label("SignUpGenius", systemImage: "square.and.arrow.down") }
        }
        .frame(width: 560)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
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
                    + "Start empty to choose the adults yourself; a free room is still picked, and Suggest a Board "
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
                    .disabled(Int(portText) == model.port || Int(portText) == nil)
            } header: {
                Text("Sign-in station")
            } footer: {
                Text("Tablets connect to this port. 8080 is the usual choice; change it only if another program already uses it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { portText = String(model.port) }
    }

    private func applyPort() {
        guard let port = Int(portText), (1024...65535).contains(port) else {
            portText = String(model.port)
            return
        }
        model.port = port
    }
}

/// Room-card timers. They are guidance, not limits: the timers prompt
/// someone to check on the room, and nothing stops a board that needs longer.
private struct TimerSettings: View {
    @Environment(AppModel.self) private var model

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
                }
                Section {
                    minutes("Running long after", \.projectYellowMinutes, event)
                    minutes("Overdue after", \.projectRedMinutes, event)
                } header: {
                    Text("Proposal review (from Start Review)")
                } footer: {
                    Text("District practice. A proposal review is not a board of review, so the Guide sets no length for it.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Open an event first", systemImage: "timer")
                .frame(height: 200)
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
                model.attempt("Could not save the settings") { try event.updateConfig(edited) }
            }
        )
    }
}

private struct SignUpGeniusSettings: View {
    @Environment(AppModel.self) private var model
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
                    }
                    .disabled(!model.signUpGeniusAllowed)
                    if saved {
                        Label("Saved in your keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
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
                    Text("Off for this run: EAGLEBOARDS_DATA_FOLDER is set, so the keychain is not read. "
                        + "Set EAGLEBOARDS_SIGNUPGENIUS=1 to use it with a scratch folder.")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Toggle("Import when today's event is opened", isOn: $model.importOnOpen)
                Button("Import Now") { Task { await model.importSignUps() } }
                    .disabled(model.event == nil || model.isImporting || !model.hasSignUpGeniusKey)
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
