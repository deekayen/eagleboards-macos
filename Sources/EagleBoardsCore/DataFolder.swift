import Foundation

/// The folder an operator keeps the event data in. The layout is the Java
/// app's working directory, so the same folder works with either program:
///
///     <data folder>/
///         config.properties           settings, kept across events
///         Master_AdultHistory.csv     every adult who has ever signed in
///         2026-09-22/                 one folder per event
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

    public func eventFolder(_ event: String) -> URL {
        root.appending(path: event, directoryHint: .isDirectory)
    }

    public func youthURL(event: String) -> URL { eventFolder(event).appending(path: "scouts.csv") }
    public func adultsURL(event: String) -> URL { eventFolder(event).appending(path: "adults.csv") }
    public func roomsURL(event: String) -> URL { eventFolder(event).appending(path: "rooms.csv") }
    public func scheduledYouthURL(event: String) -> URL { eventFolder(event).appending(path: "scouts_scheduled.csv") }

    /// Events already in the folder, newest first.
    public func events() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names
            .filter { Timestamp.isDayStamp($0) }
            .filter { name in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: eventFolder(name).path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .sorted(by: >)
    }
}
