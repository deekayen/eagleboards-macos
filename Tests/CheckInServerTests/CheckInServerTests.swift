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
        ("/", "text/html", "Please sign in"),
        ("/youth_register", "text/html", "Youth sign-in"),
        ("/adult_register", "text/html", "Adult sign-in"),
        ("/checkin.css", "text/css", "WCAG 2.2 AA"),
        ("/checkin.js", "text/javascript", "ebSignInForm"),
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
    /// door can read the adult history or move a board. Nothing here reads a
    /// query string either, so there is no filter that could match a youth's
    /// phone number or birthdate and say whose it is (SPEC.md D-7, D-8).
    @Test(arguments: [
        "/scheduler", "/admin", "/configure", "/help",
        "/youth-cells?cols=Email,Phone,DOB", "/adult-cells", "/adult-history-cells", "/room-cells",
        "/youth-cells?cols=Last&filter=Phone~555-0101", "/youth-cells?cols=Last&filter=DOB~2011-02-03",
        "/youth-scheduled-cells?cols=Last,Phone", "/youth-scheduled-cells?cols=Last,Phone&fmt=csv&filename=Youth.csv",
        "/adult-autofill?op=list", "/youth-autofill?op=list", "/config-autofill?Name=DEFAULT",
        "/youth-autofill?Email=Lena.Lookup@Example.org&fmt=json",
        "/../Package.swift", "/checkin.js/../../Package.swift", "/index.html",
    ])
    func operatorPagesAndRecordsAreNotReachable(path: String) async throws {
        #expect(try await send(path).status == .notFound)
    }

    @Test(arguments: [
        "/seat-board", "/complete-board", "/reset-board", "/adult-update", "/room-update", "/update-config",
        "/youth-update", "/youth-scheduled-update",
    ])
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
        #expect(night.scouts.first?.dateOfBirth == "", "a birthdate from an older cached page is not kept (D-7)")
        #expect(night.scouts.first?.phone == "", "nor is a phone number (D-8)")

        let lists = try await send("/api/checked-in")
        #expect(lists.status == .ok)
        let youth = try #require(lists.json["youth"] as? [[String: String]])
        #expect(youth.count == 1)
        #expect(Set(youth[0].keys) == ["time", "last", "first", "unitType", "unit"])
        #expect(!lists.body.contains("jan@example.org"))
        #expect(!lists.body.contains("770-555-0100"))
        #expect(lists.json["refreshSeconds"] as? Int == 30)
    }

    @Test func theAdultFormListsYouthByNameAndUnitOnly() async throws {
        _ = try await send("/register-youth", method: .post,
            form: "First=Jan&Last=Doe&Email=jan%40example.org&Phone=770-555-0100&UnitType=Troop&Unit=1776&BoardType=Final")
        let reply = try await send("/api/scout-choices")
        #expect(reply.status == .ok)
        let youth = try #require(try JSONSerialization.jsonObject(with: Data(reply.body.utf8)) as? [[String: String]])
        #expect(youth.count == 1)
        #expect(Set(youth[0].keys) == ["id", "first", "last", "unitType", "unit"])
        #expect(youth[0]["id"] == "SCOUT:Doe:Jan:1776")
        #expect(!reply.body.contains("jan@example.org"))
        #expect(!reply.body.contains("770-555-0100"))
        #expect(night.scouts.first?.phone == "", "a phone number from an older cached page is not kept (D-8)")
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
        history.phone = "770-555-0110"
        try night.updateAdult(history, history: true)
        // A pre-registration from before D-7 and D-8 may still hold both.
        var scheduled = try #require(night.scheduledYouth(matchingEmail: "jan@example.org"))
        scheduled.phone = "770-555-0100"
        scheduled.dateOfBirth = "1/2/2010"
        try night.updateYouth(scheduled, scheduled: true)

        let youth = try await send("/api/youth-lookup", method: .post, form: "email=JAN%40example.org")
        #expect(youth.json["First"] as? String == "Jan")
        #expect(youth.json["Leader"] as? String == "Lee Leader")
        #expect(Set(youth.json.keys) == Set(CheckInServer.youthPrefillColumns))
        #expect(youth.json["Phone"] == nil && youth.json["DOB"] == nil)
        #expect(!youth.body.contains("770-555-0100"), "a youth's phone on file is not pre-filled (D-8)")
        #expect(!youth.body.contains("1/2/2010"), "nor a birthdate (D-7)")

        let adult = try await send("/api/adult-lookup", method: .post, form: "email=morgan%40example.org")
        #expect(adult.json["Last"] as? String == "Member")
        #expect(adult.json["Phone"] as? String == "770-555-0110", "an adult's phone still is")
        #expect(Set(adult.json.keys) == Set(CheckInServer.adultPrefillColumns))
        #expect(!adult.body.contains("2019-05-28"), "board history stays in the app")

        #expect(try await send("/api/adult-lookup", method: .post, form: "email=nobody%40example.org").body == "{}")
        #expect(try await send("/api/adult-lookup", method: .post, form: "email=NONE").body == "{}")
    }

    /// Java evening section 24, the youth phone number (SPEC.md D-8), over
    /// HTTP as the Java script does it. BoardEveningTests follows the same
    /// youth through the data files, the report and the Records window.
    @Test func aYouthsPhoneNumberIsNotKeptButAnAdultsStillFillsTheirForm() async throws {
        let oldPage = "Last=Oldpage&First=Olive&Email=op%40example.org&Phone=555-0101&UnitType=Troop&Unit=4402&BoardType=Final&DOB=2011-02-03"
        #expect(try await send("/register-youth", method: .post, form: oldPage).body == "OK.")
        var olive = try #require(night.scout(id: "SCOUT:Oldpage:Olive:4402"))
        #expect(olive.phone == "" && olive.dateOfBirth == "", "neither is kept from an old cached page")

        // One on file from before D-7 and D-8, put there in the Records window.
        olive.phone = "555-0101"
        olive.dateOfBirth = "2011-02-03"
        try night.updateYouth(olive)
        let again = oldPage
            .replacingOccurrences(of: "555-0101", with: "555-0199")
            .replacingOccurrences(of: "2011-02-03", with: "2012-12-12")
        #expect(try await send("/register-youth", method: .post, form: again).body == "OK.")
        #expect(night.scout(id: olive.id)?.phone == "555-0101", "signing in again neither changes nor blanks it")
        #expect(night.scout(id: olive.id)?.dateOfBirth == "2011-02-03")
        let lists = try await send("/api/checked-in").body + send("/api/scout-choices").body
        #expect(!lists.contains("555-0101") && !lists.contains("2011-02-03"), "and the lists at the door never carry it")

        _ = try await send(
            "/register-adult", method: .post,
            form: "Last=Phoneon&First=Adele&Email=adele%40example.org&Phone=555-0102&UnitType=Troop&Unit=4403&ProjectReview=Member&FinalBoard=Member"
        )
        let adult = try await send("/api/adult-lookup", method: .post, form: "email=adele%40example.org")
        #expect(adult.json["Phone"] as? String == "555-0102", "an adult's phone number still fills in their form")
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
        #expect(String(decoding: data, as: UTF8.self).contains("Please sign in"))

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
