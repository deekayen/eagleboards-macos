import EagleBoardsCore
import Foundation
import Testing

// The board rules, auto-select and fill the rest, as the cases all three
// versions share (SPEC.md D-5). Resources/cases/ is a byte-for-byte copy of
// eagleboards-shared/cases, pinned by test-cases.lock and checked in CI; a
// new case goes there, never only here (see its README for the format).
//
// Each case runs through the Mac's own code and the answer is mapped into
// the cases' shapes. A comparison is never loosened to make a case pass: a
// case that fails means the Mac, or the case, is wrong, and a real
// difference is settled in eagleboards-shared first.

/// A JSON value, so a case can be compared the way it is written.
enum JSON: Sendable, Equatable, Decodable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let bool = try? value.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let array = try? value.decode([JSON].self) {
            self = .array(array)
        } else {
            self = .object(try value.decode([String: JSON].self))
        }
    }

    subscript(key: String) -> JSON {
        if case .object(let object) = self { object[key] ?? .null } else { .null }
    }

    /// A missing or null field is blank, as the cases' README says.
    var string: String {
        if case .string(let string) = self { string } else { "" }
    }

    var array: [JSON] {
        if case .array(let array) = self { array } else { [] }
    }

    var object: [String: JSON]? {
        if case .object(let object) = self { object } else { nil }
    }

    var int: Int? {
        if case .number(let number) = self { Int(exactly: number) } else { nil }
    }

    var description: String {
        switch self {
        case .null: "null"
        case .bool(let bool): "\(bool)"
        case .number(let number): number == number.rounded() ? "\(Int(number))" : "\(number)"
        case .string(let string): "\"\(string)\""
        case .array(let array): "[" + array.map(\.description).joined(separator: ", ") + "]"
        case .object(let object):
            "{" + object.keys.sorted().map { "\"\($0)\": \(object[$0]!)" }.joined(separator: ", ") + "}"
        }
    }
}

/// One case, named in the test list as "op: name", so a failure reads the
/// same in every version.
struct SharedCase: Sendable, CustomTestStringConvertible {
    let op: String
    let name: String
    let body: JSON
    var testDescription: String { "\(op): \(name)" }
}

enum SharedCases {
    static let format = 1.0
    static let ops = ["unit-conflicts", "outside-member", "board-size", "suggest", "fill", "free-since",
                      "seat-down-the-queue", "support-link"]

    struct File: Sendable {
        let name: String
        let suite: JSON?
        let error: String?
    }

    static let files: [File] = {
        guard let folder = Bundle.module.url(forResource: "cases", withExtension: nil),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        return names.filter { $0.hasSuffix(".json") }.sorted().map { name in
            do {
                let data = try Data(contentsOf: folder.appending(path: name))
                return File(name: name, suite: try JSONDecoder().decode(JSON.self, from: data), error: nil)
            } catch {
                return File(name: name, suite: nil, error: "\(error)")
            }
        }
    }()

    /// Only files this runner reads; the others fail `everyCaseFileIsOneThisRunnerReads`.
    static let all: [SharedCase] = files.compactMap { file -> [SharedCase]? in
        guard let suite = file.suite, isReadable(suite, file: file.name) else { return nil }
        return suite["cases"].array.map { SharedCase(op: suite["op"].string, name: $0["name"].string, body: $0) }
    }.flatMap { $0 }

    static func isReadable(_ suite: JSON, file: String) -> Bool {
        guard case .number(let number) = suite["format"], number <= format else { return false }
        return ops.contains(suite["op"].string) && file == suite["op"].string + ".json"
    }
}

@Suite("Shared rule and auto-select cases (SPEC.md D-5)")
struct SharedCaseTests {
    @Test func everyCaseFileIsOneThisRunnerReads() {
        #expect(!SharedCases.files.isEmpty, "no case files in the test bundle")
        for file in SharedCases.files {
            guard let suite = file.suite else {
                Issue.record("\(file.name) is not readable JSON: \(file.error ?? "")")
                continue
            }
            #expect(SharedCases.isReadable(suite, file: file.name),
                    "\(file.name): format \(suite["format"]) or op \(suite["op"]) is not one this runner reads")
        }
    }

    @Test(arguments: SharedCases.all)
    func sharedCase(_ sharedCase: SharedCase) {
        let body = sharedCase.body
        let expect = body["expect"]
        switch sharedCase.op {
        case "unit-conflicts":
            let conflicts = BoardRules.unitConflicts(scoutUnitName: body["youth"]["unit"].string,
                                                     members: body["adults"].array.map(adult))
            #expect(JSON.array(conflicts.map { .string($0.id) }) == expect)

        case "outside-member":
            let outside = BoardRules.hasMemberFromOutsideUnit(scoutUnitName: body["youth"]["unit"].string,
                                                              members: body["adults"].array.map(adult))
            #expect(JSON.bool(outside) == expect)

        case "board-size":
            guard let count = body["count"].int else {
                Issue.record("count is not a whole number: \(body["count"])")
                return
            }
            switch BoardType(rawValue: body["boardType"].string) {
            case .finalBoard:
                #expect(JSON.string(word(BoardRules.checkBoardSize(count))) == expect)
                #expect(JSON.string(word(BoardRules.checkSize(count, for: .finalBoard))) == expect)
            case .projectReview:
                #expect(JSON.string(word(BoardRules.checkProjectSize(count))) == expect)
                #expect(JSON.string(word(BoardRules.checkSize(count, for: .projectReview))) == expect)
            case nil:
                Issue.record("unknown boardType \(body["boardType"])")
            }

        case "suggest":
            let adults = body["adults"].array.map(adult)
            let youth = youth(body["youth"])
            let pick = BoardSuggestion(for: youth, adults: adults, rooms: [freeRoom(for: youth)],
                                       waiting: body["waiting"].array.map(self.youth), freeSince: freeSince(body["adults"]))
            // The Mac's suggestion lists the whole board, chair first.
            if let chair = pick.chairID {
                #expect(pick.memberIDs.first == chair, "the chair leads the board")
            }
            let members = pick.chairID == nil ? pick.memberIDs : Array(pick.memberIDs.dropFirst())
            compare(proposal(chair: pick.chairID, members: members, problems: pick.problems), expect)

        case "fill":
            let youth = youth(body["youth"])
            let fill = BoardSuggestion.fill(for: youth, adults: body["adults"].array.map(adult),
                                            picked: body["picked"].array.map(\.string),
                                            waiting: body["waiting"].array.map(self.youth), freeSince: freeSince(body["adults"]))
            compare(proposal(chair: fill.chairID, members: fill.memberIDs, problems: fill.problems), expect)

        case "free-since":
            let since = BoardSuggestion.freeSinceTimes(
                adults: body["adults"].array.map { Adult(fields: ["Type": "ADULT", "ID": $0["id"].string, "RegTime": $0["regTime"].string]) },
                scouts: body["boards"].array.map {
                    Scout(fields: ["Type": "SCOUT", "Status": $0["status"].string,
                                   "BoardMembersIDs": $0["members"].string, "LastUpdateTime": $0["lastUpdate"].string])
                })
            for (id, time) in expect.object ?? [:] {
                #expect(since[id].map(JSON.string) ?? .null == time, "\(id)")
            }

        case "seat-down-the-queue":
            // The procedure in the cases' README: down the queue in order, each
            // youth's proposal weighing every other youth not yet seated; a
            // proposal with no problems seats a board and puts its adults in a room.
            var adults = body["adults"].array.map(adult)
            let queue = body["queue"].array.map(youth)
            var seated = Set<String>()
            var boards = ["Final": 0, "Project": 0]
            for (index, youth) in queue.enumerated() {
                let waiting = queue.filter { $0.id != youth.id && !seated.contains($0.id) }
                let pick = BoardSuggestion(for: youth, adults: adults, rooms: [freeRoom(for: youth)], waiting: waiting)
                guard pick.problems.isEmpty, let boardType = youth.boardType else { continue }
                seated.insert(youth.id)
                boards[boardType.rawValue, default: 0] += 1
                for adultIndex in adults.indices where pick.memberIDs.contains(adults[adultIndex].id) {
                    adults[adultIndex].room = "R\(index)"
                }
            }
            #expect(JSON.object(boards.mapValues { .number(Double($0)) }) == expect)

        case "support-link":
            let supporting = Adult.withSupportLink(body["supporting"].string, body["youth"].string,
                                                   linked: body["linked"] == .bool(true))
            #expect(JSON.string(supporting) == expect)

        default:
            Issue.record("unknown op \(sharedCase.op)")
        }
    }

    // MARK: The cases' vocabulary into the Mac's

    private func adult(_ json: JSON) -> Adult {
        Adult(fields: [
            "Type": "ADULT", "ID": json["id"].string, "UnitName": json["unit"].string,
            "FinalBoard": json["final"].string, "ProjectReview": json["project"].string, "Room": json["room"].string,
            "Supporting": json["supporting"].string, "WoodBadge": json["woodBadge"].string,
        ])
    }

    private func youth(_ json: JSON) -> Scout {
        Scout(fields: [
            "Type": "SCOUT", "ID": json["id"].string, "UnitName": json["unit"].string,
            "BoardType": json["boardType"].string, "Status": BoardStatus.registered.rawValue,
        ])
    }

    /// Rooms are not part of the cases: the suggestion is given one free room
    /// of the youth's kind, so a room shortage never shows up as a problem.
    private func freeRoom(for youth: Scout) -> Room {
        Room(fields: ["Type": "ROOM", "ID": "ROOM:1", "Room": "1", "BoardType": youth["BoardType"]])
    }

    /// The suggestion takes when each adult was last free as its own
    /// argument; the cases write it on the adult.
    private func freeSince(_ adults: JSON) -> [String: String] {
        Dictionary(adults.array.map { ($0["id"].string, $0["freeSince"].string) }, uniquingKeysWith: { first, _ in first })
    }

    private func word(_ verdict: BoardRules.SizeVerdict) -> String {
        switch verdict {
        case .tooFew: "too-few"
        case .ok: "ok"
        case .overPreferred: "over-preferred"
        case .tooMany: "too-many"
        }
    }

    /// The Mac words its shortages its own way, so they are compared as the
    /// cases' structures. A message this does not know is a failure.
    private func proposal(chair: String?, members: [String], problems: [String]) -> [String: JSON] {
        [
            "chair": chair.map(JSON.string) ?? .null,
            "members": .array(members.map(JSON.string)),
            "problems": .array(problems.map { text in
                if text.wholeMatch(of: /No (Final Board|Proposal Review) chairs are available\./) != nil {
                    return .object(["kind": .string("no-chair")])
                }
                if let match = text.wholeMatch(of: /Only (\d+) (Final Board|Proposal Review) members? (is|are) available\./),
                   let count = Double(match.1) {
                    return .object(["kind": .string("too-few-members"), "available": .number(count)])
                }
                Issue.record("unknown problem message \"\(text)\"")
                return .string(text)
            }),
        ]
    }

    /// Only the keys the case names are compared; any other key, or a problem
    /// kind the README does not define, is a mistake in the case.
    private func compare(_ got: [String: JSON], _ expect: JSON) {
        guard let expected = expect.object else {
            Issue.record("expect is not an object: \(expect)")
            return
        }
        for problem in expected["problems"]?.array ?? [] where !["no-chair", "too-few-members"].contains(problem["kind"].string) {
            Issue.record("unknown problem kind \(problem["kind"]) in the case")
        }
        for (key, want) in expected.sorted(by: { $0.key < $1.key }) {
            guard let value = got[key] else {
                Issue.record("unknown key \"\(key)\" in expect")
                continue
            }
            #expect(value == want, "\(key)")
        }
    }
}
