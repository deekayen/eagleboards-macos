import Foundation

/// One filled slot from a SignUpGenius sign-up.
public struct SignUpEntry: Sendable, Equatable {
    public var startDate: String
    public var firstName: String
    public var lastName: String
    /// The slot's name, e.g. "Adult Board Member" or "Eagle Board of Review".
    public var item: String
    public var email: String
    /// The sign-up's custom questions, in order: unit, phone, leader.
    public var customAnswers: [String]

    public init(startDate: String, firstName: String, lastName: String, item: String, email: String, customAnswers: [String]) {
        self.startDate = startDate
        self.firstName = firstName
        self.lastName = lastName
        self.item = item
        self.email = email
        self.customAnswers = customAnswers
    }

    public var isAdultSlot: Bool { item.lowercased().contains("adult") }
    public var unitText: String { customAnswers.count > 0 ? customAnswers[0] : "" }
    public var phoneText: String { customAnswers.count > 1 ? customAnswers[1] : "" }
    public var leaderText: String { customAnswers.count > 2 ? customAnswers[2] : "" }
}

/// The two SignUpGenius API calls the import makes.
///
/// The API takes the key as a query parameter, so request URLs contain it.
/// Nothing here logs a URL or puts one in an error message.
public struct SignUpGeniusClient: Sendable {
    public let apiKey: String
    public let session: URLSession
    public let baseURL: URL

    public init(apiKey: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.signupgenius.com/v2/k")!) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    public struct Signup: Sendable, Equatable {
        public let id: String
        public let title: String
    }

    /// The active sign-up whose title mentions both "eagle" and "board" and
    /// whose date range covers `today` (`YYYY-MM-DD`).
    public func findActiveSignup(today: String) async throws -> Signup {
        let json = try await fetch(path: "signups/created/active/")
        let candidates = (json["data"] as? [[String: Any]]) ?? []
        for signup in candidates {
            let title = Self.text(signup["title"])
            let lowercasedTitle = title.lowercased()
            // Compared on the date alone: the API's strings carry a time too, and
            // "2026-09-22" sorts before "2026-09-22 18:00", which would miss a
            // sign-up on its first day.
            let startDay = String(Self.text(signup["startdatestring"]).prefix(10))
            let endDay = String(Self.text(signup["enddatestring"]).prefix(10))
            if today >= startDay, today <= endDay,
               lowercasedTitle.contains("eagle"), lowercasedTitle.contains("board") {
                return Signup(id: Self.text(signup["signupid"]), title: title)
            }
        }
        throw EventError("SignUpGenius has no active Eagle board sign-up covering \(today).")
    }

    /// Every filled slot in the sign-up.
    public func filledSlots(signupID: String) async throws -> [SignUpEntry] {
        let json = try await fetch(path: "signups/report/filled/\(signupID)/")
        let data = json["data"] as? [String: Any]
        let slots = (data?["signup"] as? [[String: Any]]) ?? []
        return slots.map { slot in
            let answers = (slot["customfields"] as? [[String: Any]] ?? []).map { Self.text($0["value"]) }
            return SignUpEntry(
                startDate: Self.text(slot["startdatestring"]),
                firstName: Self.text(slot["firstname"]),
                lastName: Self.text(slot["lastname"]),
                item: Self.text(slot["item"]),
                email: Self.text(slot["email"]),
                customAnswers: answers
            )
        }
    }

    private func fetch(path: String) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "user_key", value: apiKey)]
        let response: (Data, URLResponse)
        do {
            response = try await session.data(from: components.url!)
        } catch {
            throw EventError("Could not reach SignUpGenius: \(error.localizedDescription)")
        }
        if let http = response.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EventError("SignUpGenius answered with HTTP \(http.statusCode). Check the API key in Settings.")
        }
        guard let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any] else {
            throw EventError("SignUpGenius sent something that is not JSON.")
        }
        return json
    }

    /// JSON values as text, the way Jackson's `asText()` gave them to the Java app.
    static func text(_ value: Any?) -> String {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }
}

/// Tidying what people typed into SignUpGenius before it becomes a record.
public enum NameCleanup {
    /// Trimmed, inner whitespace collapsed, first letter capitalized.
    public static func name(_ raw: String) -> String {
        let words = raw.split(whereSeparator: \.isWhitespace)
        return words.map(String.init).joined(separator: " ").capitalizingFirstLetter
    }

    /// Each word capitalized, e.g. "jane doe" -> "Jane Doe".
    public static func leader(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).map { String($0).capitalizingFirstLetter }.joined(separator: " ")
    }

    /// `770-555-1234` from ten digits (or eleven with a leading 1), `555-1234`
    /// from seven. Anything else is kept as typed rather than guessed at.
    public static func phone(_ raw: String) -> String {
        var digits = Array(raw.filter { $0.isASCII && $0.isNumber })
        if digits.count == 11 && digits.first == "1" {
            digits.removeFirst()
        }
        func group(_ range: Range<Int>) -> String {
            String(digits[range])
        }
        switch digits.count {
        case 10: return "\(group(0..<3))-\(group(3..<6))-\(group(6..<10))"
        case 7: return "\(group(0..<3))-\(group(3..<7))"
        default: return raw.trimmingCharacters(in: .whitespaces)
        }
    }

    /// "Troop 1776", "T1776", "crew 12" -> type and number. Defaults to Troop.
    public static func unit(from raw: String) -> (type: UnitType, number: String) {
        let number = raw.filter { $0.isASCII && $0.isNumber }
        let lowercased = raw.lowercased().trimmingCharacters(in: .whitespaces)
        let wordMatch = UnitType.allCases.first { lowercased.hasPrefix($0.rawValue.lowercased()) }
        if let wordMatch {
            return (wordMatch, number)
        }
        switch lowercased.first {
        case "c": return (.crew, number)
        case "p": return (.pack, number)
        case "s": return (.ship, number)
        default: return (.troop, number)
        }
    }

    /// Which review a youth's slot is for. "project" or "proposal" means a
    /// proposal review; otherwise "review" or "board" means a final board.
    public static func boardType(fromSlot item: String) -> BoardType? {
        let lowercased = item.lowercased()
        if lowercased.contains("project") || lowercased.contains("proposal") {
            return .projectReview
        }
        if lowercased.contains("review") || lowercased.contains("board") {
            return .finalBoard
        }
        return nil
    }
}

extension String {
    var capitalizingFirstLetter: String {
        guard let first, first.isLetter else { return self }
        return first.uppercased() + dropFirst()
    }
}
