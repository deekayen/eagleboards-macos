import EagleBoardsCore
import Foundation
import Testing

/// A throwaway preferences domain, so these never read or write the real one.
private func scratchDefaults() -> (UserDefaults, String) {
    let suite = "eagleboards-tests-\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
}

@Suite("Launch settings")
struct LaunchSettingsTests {
    @Test func aScratchFolderKeepsSignUpGeniusOut() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/Users/chair/Eagle Boards", forKey: LaunchSettings.Keys.dataFolderPath)

        let launch = LaunchSettings(environment: ["EAGLEBOARDS_DATA_FOLDER": "/tmp/eb-scratch"], defaults: defaults)

        #expect(launch.dataFolderPath == "/tmp/eb-scratch")
        #expect(!launch.signUpGeniusAllowed)
    }

    @Test func aScratchFolderCanOptBackIntoSignUpGenius() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let launch = LaunchSettings(
            environment: ["EAGLEBOARDS_DATA_FOLDER": "/tmp/eb-scratch", "EAGLEBOARDS_SIGNUPGENIUS": "1"],
            defaults: defaults
        )

        #expect(launch.signUpGeniusAllowed)
    }

    @Test func theSavedFolderUsesSignUpGeniusAndImportsByDefault() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/Users/chair/Eagle Boards", forKey: LaunchSettings.Keys.dataFolderPath)

        let launch = LaunchSettings(environment: [:], defaults: defaults)

        #expect(launch.dataFolderPath == "/Users/chair/Eagle Boards")
        #expect(launch.signUpGeniusAllowed)
        #expect(launch.importOnOpen)
        #expect(launch.port == LaunchSettings.defaultPort)
    }

    /// `-importSignUpsOnOpen NO -checkInPort 18123` on the command line
    /// reaches the defaults as strings, not a Bool and an Int.
    @Test func commandLineStringsCount() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("NO", forKey: LaunchSettings.Keys.importOnOpen)
        defaults.set("18123", forKey: LaunchSettings.Keys.port)

        let launch = LaunchSettings(environment: [:], defaults: defaults)

        #expect(!launch.importOnOpen)
        #expect(launch.port == 18123)
    }

    @Test func thePortVariableWinsOverTheSavedPort() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(9090, forKey: LaunchSettings.Keys.port)

        #expect(LaunchSettings(environment: ["EAGLEBOARDS_PORT": "18123"], defaults: defaults).port == 18123)
        #expect(LaunchSettings(environment: [:], defaults: defaults).port == 9090)
    }

    /// What Settings accepts as the sign-in station's port.
    @Test func aPortIsAWholeNumberFrom1024To65535() {
        #expect(LaunchSettings.port(from: "8080") == 8080)
        #expect(LaunchSettings.port(from: " 18123 ") == 18123, "spaces around it are ignored")
        #expect(LaunchSettings.port(from: "1024") == 1024 && LaunchSettings.port(from: "65535") == 65535, "both ends are in")
        for refused in ["1023", "65536", "0", "-8080", "80.5", "8080a", "eighty", ""] {
            #expect(LaunchSettings.port(from: refused) == nil, "\(refused) is not a port")
        }
    }

    /// When the station cannot start, the words say what else may hold the
    /// port, and the range Settings takes.
    @Test func aPortProblemSaysWhatToDo() {
        #expect(LaunchSettings.portInUse(8080) == "Port 8080 is already in use. Another copy of Eagle Boards or the Java "
            + "Eagle Board Scheduler may be running. Quit it and try again, or choose another port in Settings › General.")
        #expect(LaunchSettings.portRefused(80) == "macOS would not let Eagle Boards listen on port 80. "
            + "Choose a port from 1024 to 65535 in Settings › General.", "1024 itself is allowed")
    }

    // A screenshot run shows dark or light without changing the Mac's setting.
    @Test func theAppearanceVariableIsForOneRunOnly() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LaunchSettings(environment: [:], defaults: defaults).appearance == nil, "the system's, as always")
        #expect(LaunchSettings(environment: ["EAGLEBOARDS_APPEARANCE": "dark"], defaults: defaults).appearance == .dark)
        #expect(LaunchSettings(environment: ["EAGLEBOARDS_APPEARANCE": "Light"], defaults: defaults).appearance == .light)
        #expect(LaunchSettings(environment: ["EAGLEBOARDS_APPEARANCE": "purple"], defaults: defaults).appearance == nil)
        #expect((defaults.persistentDomain(forName: suite) ?? [:]).keys
            .allSatisfy { !$0.localizedCaseInsensitiveContains("appearance") }, "and nothing is saved")
    }
}

/// Whether selecting a waiting youth proposes a board, or leaves it for the
/// operator to pick.
@Suite("Proposing boards")
struct ProposeBoardsSettingTests {
    @Test func boardsAreProposedUnlessTurnedOff() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LaunchSettings(environment: [:], defaults: defaults).proposeBoards)

        defaults.set(false, forKey: LaunchSettings.Keys.proposeBoards)
        #expect(!LaunchSettings(environment: [:], defaults: defaults).proposeBoards)
    }

    @Test func theCommandLineCanTurnItOff() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("NO", forKey: LaunchSettings.Keys.proposeBoards)
        #expect(!LaunchSettings(environment: [:], defaults: defaults).proposeBoards)
    }
}
