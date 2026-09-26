import EagleBoardsCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            TimerSettings()
                .tabItem { Label("Timers", systemImage: "timer") }
            ColorSettings()
                .tabItem { Label("Colors", systemImage: "paintpalette") }
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
        Form {
            Section("Data folder") {
                LabeledContent("Folder", value: model.dataFolder?.root.path ?? "Not chosen")
                HStack {
                    Button("Choose…") { model.chooseDataFolderWithPanel() }
                    Button("Show in Finder") { model.showDataFolderInFinder() }
                        .disabled(model.night == nil)
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

/// Room-card timers. They are guidance, not limits: the colors prompt
/// someone to check on the room, and nothing stops a board that needs longer.
private struct TimerSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let night = model.night {
            Form {
                Section {
                    minutes("Convening, red after", \.conveneRedMinutes, night)
                } header: {
                    Text("Board convening (Seat Board to Start Review)")
                } footer: {
                    Text("Guide to Advancement 8.0.3.0 #8: members convene at least 30 minutes before the board to go over the "
                        + "application, references and project workbook. Used here as a cap: past it the youth is being kept "
                        + "waiting. There is no yellow, because it is a limit rather than a target.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    minutes("Yellow after", \.finalYellowMinutes, night)
                    minutes("Red after", \.finalRedMinutes, night)
                } header: {
                    Text("Final board review (from Start Review)")
                } footer: {
                    Text("Guide to Advancement 8.0.3.0 #9: Eagle boards generally last 30 minutes or somewhat longer, but "
                        + "rarely should one last longer than 45 minutes.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    minutes("Yellow after", \.projectYellowMinutes, night)
                    minutes("Red after", \.projectRedMinutes, night)
                } header: {
                    Text("Proposal review (from Start Review)")
                } footer: {
                    Text("District practice. A proposal review is not a board of review, so the Guide sets no length for it.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Stepper(value: configBinding(\.refreshSeconds, night), in: 5...300, step: 5) {
                        LabeledContent("Refresh every", value: "\(night.config.refreshSeconds) seconds")
                    }
                } header: {
                    Text("Sign-in station")
                } footer: {
                    Text("How often the lists of who has signed in refresh on the tablet. The scheduler here updates immediately.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Open a night first", systemImage: "timer")
                .frame(height: 200)
        }
    }

    private func minutes(_ label: String, _ keyPath: WritableKeyPath<Config, Int>, _ night: EventNight) -> some View {
        Stepper(value: configBinding(keyPath, night), in: 0...240) {
            LabeledContent(label, value: night.config[keyPath: keyPath] == 0 ? "off" : "\(night.config[keyPath: keyPath]) min")
        }
    }

    private func configBinding(_ keyPath: WritableKeyPath<Config, Int>, _ night: EventNight) -> Binding<Int> {
        Binding(
            get: { night.config[keyPath: keyPath] },
            set: { newValue in
                var edited = night.config
                edited[keyPath: keyPath] = newValue
                model.attempt { try night.updateConfig(edited) }
            }
        )
    }
}

private struct ColorSettings: View {
    @Environment(AppModel.self) private var model
    private let statuses: [BoardStatus] = [.registered, .seated, .inProgress, .completed, .postponed]

    var body: some View {
        if let night = model.night {
            Form {
                Section {
                    ForEach(statuses, id: \.self) { status in
                        HStack {
                            Text(status.label)
                            Spacer()
                            ColorPicker("Status badge", selection: colorBinding(status, highlighted: false, night), supportsOpacity: false)
                                .labelsHidden()
                            StatusBadge(statusText: status.rawValue, config: night.config)
                                .frame(width: 100)
                        }
                    }
                } footer: {
                    Text("Status badges use these colors. They are saved in config.properties, which the Java Eagle Board Scheduler reads too.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Restore Default Colors") {
                        var edited = night.config
                        for status in BoardStatus.allCases {
                            for highlighted in [false, true] {
                                edited.setColorHex(Config.standard.colorHex(for: status, highlighted: highlighted), for: status, highlighted: highlighted)
                            }
                        }
                        model.attempt { try night.updateConfig(edited) }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Open a night first", systemImage: "paintpalette")
                .frame(height: 200)
        }
    }

    private func colorBinding(_ status: BoardStatus, highlighted: Bool, _ night: EventNight) -> Binding<Color> {
        Binding(
            get: { night.config.color(for: status, highlighted: highlighted) },
            set: { color in
                var edited = night.config
                edited.setColorHex(color.hexString, for: status, highlighted: highlighted)
                model.attempt { try night.updateConfig(edited) }
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
                Text("With a key, Eagle Boards reads tonight's Eagle board sign-up: youth become pre-registrations, so their "
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
                Toggle("Import when tonight is opened", isOn: $model.importOnOpen)
                Button("Import Now") { Task { await model.importSignUps() } }
                    .disabled(model.night == nil || model.isImporting || !model.hasSignUpGeniusKey)
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
