@testable import CheckInServer
import EagleBoardsCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing

/// What the sign-in tablets can and cannot reach.
@MainActor
@Suite("Check-in server")
struct CheckInServerTests {
    let scratch: ScratchFolder
    let night: EventNight

    init() throws {
        scratch = try ScratchFolder()
        night = try EventNight(folder: DataFolder(root: scratch.url), night: "2026-09-22")
    }

    struct Reply: Sendable {
        let status: HTTPResponse.Status
        let headers: HTTPFields
        let body: String
        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]) ?? [:]
        }
    }

    private func send(_ uri: String, method: HTTPRequest.Method = .get, form: String? = nil) async throws -> Reply {
        let application = Application(router: CheckInServer.router(for: night))
        return try await application.test(.router) { client in
            let response = try await client.execute(
                uri: uri,
                method: method,
                headers: form == nil ? [:] : [.contentType: "application/x-www-form-urlencoded"],
                body: form.map { ByteBuffer(string: $0) }
            )
            return Reply(status: response.status, headers: response.headers, body: String(buffer: response.body))
        }
    }

    @Test(arguments: [
        ("/", "text/html", "Please Sign In"),
        ("/youth_register", "text/html", "Youth Sign-In"),
        ("/adult_register", "text/html", "Adult Sign-In"),
        ("/checkin.css", "text/css", "eb-public"),
        ("/checkin.js", "text/javascript", "ebWireRegistration"),
    ])
    func theSignInPagesAreServed(path: String, contentType: String, marker: String) async throws {
        let reply = try await send(path)
        #expect(reply.status == .ok)
        #expect(reply.headers[.contentType]?.hasPrefix(contentType) == true)
        #expect(reply.body.contains(marker))
        #expect(reply.headers[.cacheControl] == "no-store")
        #expect(reply.headers[.init("X-Frame-Options")!] == "DENY")
    }

    /// The operator's screens are windows in the Mac app. None of the Java
    /// app's operator pages or record endpoints exist here, so nobody at the
    /// door can read the adult history or move a board.
    @Test(arguments: [
        "/scheduler", "/admin", "/configure", "/help",
        "/youth-cells?cols=Email,Phone,DOB", "/adult-cells", "/adult-history-cells", "/room-cells",
        "/adult-autofill?op=list", "/youth-autofill?op=list", "/config-autofill?Name=DEFAULT",
        "/../Package.swift", "/checkin.js/../../Package.swift", "/index.html",
    ])
    func operatorPagesAndRecordsAreNotReachable(path: String) async throws {
        #expect(try await send(path).status == .notFound)
    }

    @Test(arguments: ["/seat-board", "/complete-board", "/reset-board", "/adult-update", "/room-update", "/update-config"])
    func boardActionsAreNotReachable(path: String) async throws {
        #expect(try await send(path, method: .post, form: "ScoutID=x").status == .notFound)
    }

    @Test func aYouthSignsInAndAppearsOnTheListWithoutTheirContactDetails() async throws {
        let reply = try await send(
            "/register-youth", method: .post,
            form: "Email=jan%40example.org&ID=&First=Jan&Last=Doe&Phone=770-555-0100&DOB=1%2F2%2F2010&UnitType=Troop&Unit=1776&BoardType=Final&Leader=Lee+Leader"
        )
        #expect(reply.status == .ok)
        #expect(reply.body == "OK.")
        #expect(night.scouts.count == 1)
        #expect(night.scouts.first?.leader == "Lee Leader")
        #expect(night.scouts.first?.dateOfBirth == "1/2/2010")

        let lists = try await send("/api/checked-in")
        #expect(lists.status == .ok)
        let youth = try #require(lists.json["youth"] as? [[String: String]])
        #expect(youth.count == 1)
        #expect(Set(youth[0].keys) == ["time", "last", "first", "unitType", "unit"])
        #expect(!lists.body.contains("jan@example.org"))
        #expect(!lists.body.contains("770-555-0100"))
        #expect(lists.json["refreshSeconds"] as? Int == 30)
    }

    @Test func aRefusalComesBackInWords() async throws {
        let reply = try await send("/register-adult", method: .post, form: "First=&Last=")
        #expect(reply.status == .badRequest)
        #expect(reply.body.contains("first and last name"))
        #expect(night.adults.isEmpty)
    }

    @Test func anAdultSignsIn() async throws {
        let reply = try await send(
            "/register-adult", method: .post,
            form: "Email=morgan%40example.org&First=Morgan&Last=Member&Phone=555&UnitType=District&Unit=&FinalBoard=Chair&ProjectReview=Member"
        )
        #expect(reply.status == .ok)
        #expect(night.adults.first?.unitName == "District")
        #expect(night.adultHistory.count == 1)
    }

    @Test func lookupsFillTheFormAndNothingMore() async throws {
        try night.mergeSignUps([
            SignUpEntry(startDate: "2026-09-22", firstName: "jan", lastName: "doe", item: "Eagle Board of Review",
                        email: "jan@example.org", customAnswers: ["Troop 1776", "7705550100", "lee leader"]),
        ], month: "2026-09")
        try night.registerAdult(["First": "Morgan", "Last": "Member", "Email": "morgan@example.org", "UnitType": "Troop", "Unit": "5"])
        var history = try #require(night.adultHistory.first)
        history.boardHistory = "(2019-05-28)(2026-08-25)"
        try night.updateAdult(history, history: true)

        let youth = try await send("/api/youth-lookup", method: .post, form: "email=JAN%40example.org")
        #expect(youth.json["First"] as? String == "Jan")
        #expect(youth.json["Leader"] as? String == "Lee Leader")
        #expect(Set(youth.json.keys) == Set(CheckInServer.youthPrefillColumns))

        let adult = try await send("/api/adult-lookup", method: .post, form: "email=morgan%40example.org")
        #expect(adult.json["Last"] as? String == "Member")
        #expect(Set(adult.json.keys) == Set(CheckInServer.adultPrefillColumns))
        #expect(!adult.body.contains("2019-05-28"), "board history stays in the app")

        #expect(try await send("/api/adult-lookup", method: .post, form: "email=nobody%40example.org").body == "{}")
        #expect(try await send("/api/adult-lookup", method: .post, form: "email=NONE").body == "{}")
    }

    @Test func anOversizedBodyIsRefused() async throws {
        let huge = "First=" + String(repeating: "x", count: FormFields.maximumBodyBytes + 1)
        let reply = try await send("/register-youth", method: .post, form: huge)
        #expect(reply.status == .contentTooLarge)
        #expect(night.scouts.isEmpty)
    }

    @Test func theServerListensAndStops() async throws {
        let (portStream, portContinuation) = AsyncStream<Int>.makeStream()
        let night = self.night
        let server = Task {
            try await CheckInServer.run(night: night, host: "127.0.0.1", port: 0) { port in
                portContinuation.yield(port)
            }
        }
        var ports = portStream.makeAsyncIterator()
        let port = try #require(await ports.next())
        #expect(port > 0)

        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("Please Sign In"))

        server.cancel()
        _ = await server.result
        await #expect(throws: (any Error).self) {
            _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        }
    }
}

@Suite("Form bodies")
struct FormFieldsTests {
    @Test func decodesTheWayBrowsersEncode() {
        let fields = FormFields.parse("Leader=Lee+Leader&Email=jan%40example.org&Notes=a%2Bb&Empty=&Flag&First=1&First=2")
        #expect(fields["Leader"] == "Lee Leader")
        #expect(fields["Email"] == "jan@example.org")
        #expect(fields["Notes"] == "a+b")
        #expect(fields["Empty"] == "")
        #expect(fields["Flag"] == "")
        #expect(fields["First"] == "1", "the first value wins")
    }
}

/// A throwaway data folder, removed when the test is done. Synthetic data only.
final class ScratchFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "eagleboards-server-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
