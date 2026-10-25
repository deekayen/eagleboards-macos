import EagleBoardsCore
import Foundation
import Hummingbird

/// The web server the sign-in tablets use.
///
/// It serves the three sign-in pages and the handful of calls they make, and
/// nothing else. The scheduler, the records and the settings are windows in
/// the Mac app, so someone at the door cannot type `/admin` and read every
/// adult's phone number: there is no such page to reach.
///
/// What each call returns is trimmed to what its page shows. The lists at the
/// door get names and units; the email lookups get the fields their form fills
/// in. Nobody can ask for a column by name.
public enum CheckInServer {
    /// Build the routes for an event. Split out from `run` so tests can
    /// drive them without opening a socket.
    public static func router(for event: BoardEvent) -> Router<BasicRequestContext> {
        let router = Router()
        router.middlewares.add(SecurityHeaders())

        for page in CheckInAssets.pages {
            router.get(RouterPath(page.path)) { _, _ in
                page.response()
            }
        }

        router.get("/api/checked-in") { _, _ in
            let lists = await CheckedInLists(event: event)
            return try jsonResponse(lists)
        }

        // The adult form's list of youth they will introduce (SPEC.md D-23): RSVPs and the event's
        // walk-ins not yet finished. ID, name and unit only.
        router.get("/api/scout-choices") { _, _ in
            let choices = await ScoutChoices(event: event)
            return try jsonResponse(choices.scouts)
        }

        router.post("/api/youth-lookup") { request, _ in
            let form = try await FormFields.decode(request)
            let match = await event.scheduledYouth(matchingEmail: form["email"] ?? "")
            return try jsonResponse(match.map { pick(youthPrefillColumns, from: $0) } ?? [:])
        }

        router.post("/api/adult-lookup") { request, _ in
            let form = try await FormFields.decode(request)
            let match = await event.knownAdult(matchingEmail: form["email"] ?? "")
            return try jsonResponse(match.map { pick(adultPrefillColumns, from: $0) } ?? [:])
        }

        router.post("/register-youth") { request, _ in
            let form = try await FormFields.decode(request)
            return await outcome { try await event.registerYouth(form) }
        }

        router.post("/register-adult") { request, _ in
            let form = try await FormFields.decode(request)
            return await outcome { try await event.registerAdult(form) }
        }

        return router
    }

    /// Serve `event` until the surrounding task is cancelled.
    ///
    /// - Parameters:
    ///   - host: `0.0.0.0` for every network, `127.0.0.1` for this Mac only,
    ///     or one network's address, served with 127.0.0.1 beside it.
    ///   - port: `0` picks a free port, reported through `onRunning`.
    /// - Throws: `PortInUse` when `host` is one address and another program
    ///   serves every network at `port`.
    public static func run(
        event: BoardEvent,
        host: String = SignInListening.anyAddress,
        port: Int,
        onRunning: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async throws {
        // BSD lets an address bind beside another program on 0.0.0.0 at the
        // same port, and the more specific bind then takes the connections:
        // the Java app on 8080 would lose its tablets on this network without
        // a word. Refuse, as Every Network's own bind does.
        if host != SignInListening.anyAddress, port != 0, someoneServesEveryNetwork(port: port) {
            throw PortInUse(port: port)
        }
        let responder = router(for: event).buildResponder()
        guard host != SignInListening.anyAddress, host != SignInListening.loopback else {
            try await serve(responder, host: host, port: port, onRunning: onRunning)
            return
        }
        // Hummingbird listens on one address per application. A pinned
        // address leaves out 127.0.0.1, so listen there too, as Windows does,
        // and on the port the pinned one got: port 0 picks it.
        try await withThrowingTaskGroup(of: Void.self) { group in
            let (pinnedPorts, pinnedPort) = AsyncStream<Int>.makeStream()
            group.addTask {
                defer { pinnedPort.finish() }
                try await serve(responder, host: host, port: port) { pinnedPort.yield($0) }
            }
            var ports = pinnedPorts.makeAsyncIterator()
            if let bound = await ports.next() {
                group.addTask {
                    try await serve(responder, host: SignInListening.loopback, port: bound) { _ in await onRunning(bound) }
                }
            }
            // One that fails, or stops, takes the other with it.
            try await group.next()
            group.cancelAll()
        }
    }

    private static func serve(
        _ responder: RouterResponder<BasicRequestContext>,
        host: String,
        port: Int,
        onRunning: @escaping @Sendable (Int) async -> Void
    ) async throws {
        let application = Application(
            responder: responder,
            configuration: .init(address: .hostname(host, port: port), serverName: "Eagle Boards"),
            onServerRunning: { channel in
                await onRunning(channel.localAddress?.port ?? port)
            }
        )
        try await application.runService(gracefulShutdownSignals: [])
    }

    /// Another program listens on every network at the port the station
    /// would pin an address to.
    public struct PortInUse: Error, CustomStringConvertible {
        public let port: Int
        public var description: String { "Address already in use: port \(port), on every network" }
    }

    /// Whether another socket holds 0.0.0.0 (or IPv6's dual-stack `::`) at
    /// `port`. With SO_REUSEADDR set, as on the server's own sockets, the
    /// probe's wildcard bind succeeds beside connections in TIME_WAIT and
    /// beside a specific address held at the port, and fails only on another
    /// wildcard.
    static func someoneServesEveryNetwork(port: Int) -> Bool {
        let probe = socket(AF_INET, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        var on: Int32 = 1
        setsockopt(probe, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(truncatingIfNeeded: port).bigEndian)
        address.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bound != 0 && errno == EADDRINUSE
    }

    // MARK: - What the pages are given

    /// No DOB (SPEC.md D-7) and no Phone (D-8): one already on a
    /// pre-registration stays in the file but is never sent to the tablet.
    static let youthPrefillColumns = ["ID", "Last", "First", "UnitType", "Unit", "BoardType", "Leader"]
    static let adultPrefillColumns = ["ID", "Last", "First", "Phone", "UnitType", "Unit", "FinalBoard", "ProjectReview"]

    private static func pick<Record: EventRecord>(_ columns: [String], from record: Record) -> [String: String] {
        Dictionary(uniqueKeysWithValues: columns.map { ($0, record[$0]) })
    }

    struct CheckedInLists: Codable, Sendable {
        struct Youth: Codable, Sendable {
            let time, last, first, unitType, unit: String
        }
        struct Adult: Codable, Sendable {
            let last, first, unitType, unit: String
        }
        let refreshSeconds: Int
        let youth: [Youth]
        let adults: [Adult]

        @MainActor
        init(event: BoardEvent) {
            refreshSeconds = event.config.refreshSeconds
            youth = event.scouts.map {
                Youth(time: Timestamp.hourMinute(ofRecordStamp: $0.regTime), last: $0.last, first: $0.first, unitType: $0.unitType, unit: $0.unit)
            }
            adults = event.adults.map {
                Adult(last: $0.last, first: $0.first, unitType: $0.unitType, unit: $0.unit)
            }
        }
    }

    struct ScoutChoices: Sendable {
        struct Youth: Codable, Sendable {
            let id, first, last, unitType, unit: String
        }
        let scouts: [Youth]

        @MainActor
        init(event: BoardEvent) {
            scouts = event.scoutChoices().map {
                Youth(id: $0.id, first: $0.first, last: $0.last, unitType: $0.unitType, unit: $0.unit)
            }
        }
    }

    // MARK: - Responses

    private static func jsonResponse(_ value: some Encodable) throws -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(value)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(bytes: body))
        )
    }

    /// `OK.` or the refusal in words, as the sign-in pages expect.
    private static func outcome(_ action: () async throws -> some Any) async -> Response {
        do {
            _ = try await action()
            return textResponse("OK.", status: .ok)
        } catch let refusal as EventError {
            return textResponse(refusal.message, status: .badRequest)
        } catch {
            return textResponse("Registration failed: \(error.localizedDescription)", status: .internalServerError)
        }
    }

    private static func textResponse(_ text: String, status: HTTPResponse.Status) -> Response {
        Response(
            status: status,
            headers: [.contentType: "text/plain; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(string: text))
        )
    }
}

/// `application/x-www-form-urlencoded` bodies, which is all the pages send.
enum FormFields {
    /// The biggest body a sign-in could need, with room to spare.
    static let maximumBodyBytes = 16 * 1024

    static func decode(_ request: Request) async throws -> [String: String] {
        let body = try await request.body.collect(upTo: maximumBodyBytes)
        return parse(String(buffer: body))
    }

    static func parse(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = decodeComponent(parts[0])
            let value = parts.count > 1 ? decodeComponent(parts[1]) : ""
            if !name.isEmpty && fields[name] == nil {
                fields[name] = value
            }
        }
        return fields
    }

    private static func decodeComponent(_ component: Substring) -> String {
        let spaced = component.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}

/// Headers that keep a shared tablet from holding on to what it was shown.
struct SecurityHeaders<Context: RequestContext>: RouterMiddleware {
    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        var response = try await next(request, context)
        response.headers[.cacheControl] = "no-store"
        response.headers[.init("X-Content-Type-Options")!] = "nosniff"
        response.headers[.init("X-Frame-Options")!] = "DENY"
        response.headers[.init("Referrer-Policy")!] = "no-referrer"
        return response
    }
}
