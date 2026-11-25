import EagleBoardsCore
import Foundation

/// A throwaway data folder. Tests never touch a real one: everything here is
/// synthetic, created under the system temporary directory and removed after.
final class ScratchFolder {
    let url: URL
    var dataFolder: DataFolder { DataFolder(root: url) }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "eagleboards-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func text(_ relativePath: String) throws -> String {
        try String(contentsOf: url.appending(path: relativePath), encoding: .utf8)
    }

    func write(_ text: String, to relativePath: String) throws {
        let target = url.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target)
    }
}

/// A clock the test moves by hand, for the room timers.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_790_118_300)) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(minutes: Int) {
        lock.lock()
        current += TimeInterval(minutes * 60)
        lock.unlock()
    }
}

/// Random numbers that are the same on every run for the same seed
/// (SplitMix64), so a test that tries random values never fails by chance.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
