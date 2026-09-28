import Foundation

/// What the app starts with: the saved preferences, and the environment
/// variables a developer uses to run it against a scratch folder.
///
///   EAGLEBOARDS_DATA_FOLDER      open this folder instead of the saved one
///   EAGLEBOARDS_PORT             serve sign-in on this port
///   EAGLEBOARDS_SIGNUPGENIUS=1   with a scratch folder, still use SignUpGenius
///   EAGLEBOARDS_APPEARANCE       dark or light, for this run alone
///
/// The app otherwise follows the system's appearance (SPEC.md D-16).
/// EAGLEBOARDS_APPEARANCE lets a screenshot run show dark or light without
/// changing the Mac's own setting.
///
/// A scratch folder is for synthetic people. The keychain's SignUpGenius key
/// belongs to the real district, so with EAGLEBOARDS_DATA_FOLDER set the app
/// neither reads the key nor imports, unless EAGLEBOARDS_SIGNUPGENIUS=1 says
/// to. Otherwise opening today's event would pull real youth into the scratch
/// folder and into any screenshot taken of it.
public struct LaunchSettings: Equatable, Sendable {
    public enum Keys {
        public static let dataFolderPath = "dataFolderPath"
        public static let port = "checkInPort"
        public static let importOnOpen = "importSignUpsOnOpen"
        public static let proposeBoards = "proposeBoardOnSelect"
    }

    public enum Environment {
        public static let dataFolder = "EAGLEBOARDS_DATA_FOLDER"
        public static let port = "EAGLEBOARDS_PORT"
        public static let allowSignUpGenius = "EAGLEBOARDS_SIGNUPGENIUS"
        public static let appearance = "EAGLEBOARDS_APPEARANCE"
    }

    /// An appearance chosen for one run, over the system's.
    public enum Appearance: String, Sendable {
        case dark
        case light
    }

    public static let defaultPort = 8080

    public let dataFolderPath: String?
    public let port: Int
    public let importOnOpen: Bool
    /// Selecting a waiting youth proposes a whole board. Off, the board
    /// starts empty (with a free room) for the operator to pick by hand.
    public let proposeBoards: Bool
    /// Whether the app may read the SignUpGenius key or import at all.
    public let signUpGeniusAllowed: Bool
    /// Nil follows the system, as the app always does outside a screenshot run.
    public let appearance: Appearance?

    /// Reads `defaults` through `bool(forKey:)` and `integer(forKey:)`, so a
    /// command-line `-importSignUpsOnOpen NO` or `-checkInPort 18123`, which
    /// arrive as strings, count too.
    public init(environment: [String: String], defaults: UserDefaults) {
        defaults.register(defaults: [
            Keys.port: Self.defaultPort,
            Keys.importOnOpen: true,
            Keys.proposeBoards: true,
        ])
        let scratchFolder = environment[Environment.dataFolder].flatMap { $0.isEmpty ? nil : $0 }
        dataFolderPath = scratchFolder ?? defaults.string(forKey: Keys.dataFolderPath)
        let savedPort = defaults.integer(forKey: Keys.port)
        port = Int(environment[Environment.port] ?? "") ?? (savedPort > 0 ? savedPort : Self.defaultPort)
        importOnOpen = defaults.bool(forKey: Keys.importOnOpen)
        proposeBoards = defaults.bool(forKey: Keys.proposeBoards)
        signUpGeniusAllowed = scratchFolder == nil || environment[Environment.allowSignUpGenius] == "1"
        appearance = environment[Environment.appearance].flatMap { Appearance(rawValue: $0.lowercased()) }
    }
}
