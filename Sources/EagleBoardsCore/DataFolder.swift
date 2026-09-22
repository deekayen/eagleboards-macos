import Foundation

/// The folder an operator keeps the event data in. The layout is the Java
/// app's working directory, so the same folder works with either program:
///
///     <data folder>/
///         config.properties           settings, kept across nights
///         Master_AdultHistory.csv     every adult who has ever signed in
///         2026-09-22/                 one folder per event night
///             scouts.csv
///             adults.csv
///             rooms.csv
///             scouts_scheduled.csv
///
/// Everything in here except `config.properties` is personal information,
/// much of it about minors.
public struct DataFolder: Sendable, Hashable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var configURL: URL { root.appending(path: "config.properties") }
    public var adultHistoryURL: URL { root.appending(path: "Master_AdultHistory.csv") }

    public func nightFolder(_ night: String) -> URL {
        root.appending(path: night, directoryHint: .isDirectory)
    }

    public func youthURL(night: String) -> URL { nightFolder(night).appending(path: "scouts.csv") }
    public func adultsURL(night: String) -> URL { nightFolder(night).appending(path: "adults.csv") }
    public func roomsURL(night: String) -> URL { nightFolder(night).appending(path: "rooms.csv") }
    public func scheduledYouthURL(night: String) -> URL { nightFolder(night).appending(path: "scouts_scheduled.csv") }

    /// Event nights already in the folder, newest first.
    public func nights() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names
            .filter { Timestamp.isDayStamp($0) }
            .filter { name in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: nightFolder(name).path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .sorted(by: >)
    }
}
