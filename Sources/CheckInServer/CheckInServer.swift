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
    /// Build the routes for an event night. Split out from `run` so tests can
    /// drive them without opening a socket.
    public static func router(for night: EventNight) -> Router<BasicRequestContext> {
        let router = Router()
        router.middlewares.add(SecurityHeaders())

        for page in CheckInAssets.pages {
            router.get(RouterPath(page.path)) { _, _ in
                page.response()
            }
        }

        router.get("/api/checked-in") { _, _ in
            let lists = await CheckedInLists(night: night)
            return try jsonResponse(lists)
        }

        // The adult form's "I'm here supporting" list: RSVPs and tonight's
        // walk-ins whose evening is not over. ID, name and unit only.
        router.get("/api/scout-choices") { _, _ in
            let choices = await ScoutChoices(night: night)
            return try jsonResponse(choices.scouts)
        }

        router.post("/api/youth-lookup") { request, _ in
            let form = try await FormFields.decode(request)
            let match = await night.scheduledYouth(matchingEmail: form["email"] ?? "")
            return try jsonResponse(match.map { pick(youthPrefillColumns, from: $0) } ?? [:])
        }

        router.post("/api/adult-lookup") { request, _ in
            let form = try await FormFields.decode(request)
            let match = await night.knownAdult(matchingEmail: form["email"] ?? "")
            return try jsonResponse(match.map { pick(adultPrefillColumns, from: $0) } ?? [:])
        }

        router.post("/register-youth") { request, _ in
            let form = try await FormFields.decode(request)
            return await outcome { try await night.registerYouth(form) }
        }

        router.post("/register-adult") { request, _ in
            let form = try await FormFields.decode(request)
            return await outcome { try await night.registerAdult(form) }
        }

        return router
    }

    /// Serve `night` until the surrounding task is cancelled.
    ///
    /// - Parameters:
    ///   - host: `0.0.0.0` to accept the sign-in tablets, `127.0.0.1` for this Mac only.
    ///   - port: `0` picks a free port, reported through `onRunning`.
    public static func run(
        night: EventNight,
        host: String = "0.0.0.0",
        port: Int,
        onRunning: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async throws {
        let application = Application(
            router: router(for: night),
            configuration: .init(address: .hostname(host, port: port), serverName: "Eagle Boards"),
            onServerRunning: { channel in
                await onRunning(channel.localAddress?.port ?? port)
            }
        )
        try await application.runService(gracefulShutdownSignals: [])
    }

    // MARK: - What the pages are given

    static let youthPrefillColumns = ["ID", "Last", "First", "Phone", "DOB", "UnitType", "Unit", "BoardType", "Leader"]
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
        init(night: EventNight) {
            refreshSeconds = night.config.refreshSeconds
            youth = night.scouts.map {
                Youth(time: Timestamp.hourMinute(ofRecordStamp: $0.regTime), last: $0.last, first: $0.first, unitType: $0.unitType, unit: $0.unit)
            }
            adults = night.adults.map {
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
        init(night: EventNight) {
            scouts = night.scoutChoices().map {
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
