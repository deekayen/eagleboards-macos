import Foundation

/// Someone found by name (SPEC.md D-21): the room they're in, or nil and
/// where they are instead, in words ("is waiting").
public struct PersonPlace: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isYouth: Bool
    public let room: String?
    public let whereabouts: String

    /// "Bill Amend is waiting."
    public var sentence: String { "\(name) \(whereabouts)." }
}

/// Find a person's room (SPEC.md D-21): the question is "which room is this
/// person in?", for a youth or an adult alike, so the find narrows the room
/// cards, and says where anyone it matches in no room is. The same rules and
/// test cases as the Windows version's `SchedulerLogic.FindPeople`.
public enum PersonFind {
    /// Everyone signed in whose name has `query` in it, ignoring case, youth
    /// then adults, each by last name: the room they're in, or where they are
    /// instead. An empty query finds no one.
    public static func people(_ query: String, youth: [Scout], adults: [Adult]) -> [PersonPlace] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let byName: (String, String, String, String) -> Bool = { lastA, firstA, lastB, firstB in
            let order = lastA.localizedCaseInsensitiveCompare(lastB)
            return order == .orderedSame ? firstA.localizedCaseInsensitiveCompare(firstB) == .orderedAscending : order == .orderedAscending
        }

        let foundYouth = youth.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
            .sorted { byName($0.last, $0.first, $1.last, $1.first) }
            .map { youth -> PersonPlace in
                if youth.status?.holdsRoom == true, !youth.room.isEmpty {
                    return PersonPlace(id: youth.id, name: youth.fullName, isYouth: true, room: youth.room,
                                       whereabouts: "is in room \(youth.room)")
                }
                let whereabouts = switch youth.status {
                case .completed: "has finished"
                case .postponed: "was postponed"
                default: "is waiting"
                }
                return PersonPlace(id: youth.id, name: youth.fullName, isYouth: true, room: nil, whereabouts: whereabouts)
            }
        let foundAdults = adults.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
            .sorted { byName($0.last, $0.first, $1.last, $1.first) }
            .map { adult -> PersonPlace in
                if adult.isDisabledForTonight {
                    return PersonPlace(id: adult.id, name: adult.fullName, isYouth: false, room: nil, whereabouts: "has gone home")
                }
                if adult.isOnBoard {
                    return PersonPlace(id: adult.id, name: adult.fullName, isYouth: false, room: adult.room,
                                       whereabouts: "is in room \(adult.room)")
                }
                return PersonPlace(id: adult.id, name: adult.fullName, isYouth: false, room: nil, whereabouts: "isn't on a board")
            }
        return foundYouth + foundAdults
    }

    /// The room names a find narrows the cards to: those holding someone it
    /// found, and any room whose name has the query in it. Nil for an empty
    /// query, which shows every room.
    public static func rooms(_ query: String, people found: [PersonPlace], rooms: [Room]) -> Set<String>? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        return Set(found.compactMap(\.room))
            .union(rooms.filter { $0.name.localizedCaseInsensitiveContains(query) }.map(\.name))
    }

    /// What the find says beside the rooms: where those it found in no room
    /// are, four at most and then how many more; or that it matched no one.
    /// Nil when there is nothing to say.
    public static func note(people found: [PersonPlace], roomsFound: Set<String>?) -> String? {
        guard let roomsFound else { return nil }
        let elsewhere = found.filter { $0.room == nil }
        if roomsFound.isEmpty && elsewhere.isEmpty {
            return "No one by that name has signed in."
        }
        guard !elsewhere.isEmpty else { return nil }
        let said = elsewhere.prefix(4).map(\.sentence).joined(separator: " ")
        return elsewhere.count > 4 ? "\(said) And \(elsewhere.count - 4) more." : said
    }
}
