import Foundation

// What VoiceOver hears and nothing shows (SPEC.md D-14): a step that worked,
// an Undo, who signed in at the door, a room turning long, how many rows a
// search leaves. Then the words a row or a card is read with, where the
// screen shows them in shorter form. The app only posts or shows these. The
// words follow the Windows version's (c0b18db), with the Mac's names for its
// commands.

/// The sentence a step says once it has worked.
public enum StepSpeech {
    public static func seated(_ name: String, room: String) -> String {
        "\(name)'s board is seated in room \(room). Start Review is next."
    }

    public static func reviewStarted(_ name: String, room: String) -> String {
        "\(name)'s review has started in room \(room). Complete is next."
    }

    /// Said from the record taken before the step: completing frees the room.
    public static func completed(_ name: String, result: BoardResult, room: String) -> String {
        "\(name)'s board is complete: \(result.label). Room \(room) is free."
    }

    /// Reset frees the room the board held. A board that held none names no room.
    public static func reset(_ name: String, room: String) -> String {
        room.isEmpty ? "\(name) is waiting again." : "\(name) is waiting again. Room \(room) is free."
    }

    public static func postponed(_ name: String) -> String {
        "\(name)'s board is postponed."
    }

    /// Change Members' whole change, in one announcement: one swapped for
    /// another, or who left and who joined, then a new chair.
    public static func membersChanged(before: [String], after: [String], chairBefore: String?, chairAfter: String?) -> String {
        let removed = before.filter { !after.contains($0) }
        let added = after.filter { !before.contains($0) }
        var sentences: [String] = []
        if removed.count == 1 && added.count == 1 {
            sentences.append("\(added[0]) replaces \(removed[0]) on the board.")
        } else {
            if !removed.isEmpty { sentences.append("\(list(removed)) \(removed.count == 1 ? "is" : "are") off the board.") }
            if !added.isEmpty { sentences.append("\(list(added)) \(added.count == 1 ? "is" : "are") on the board.") }
        }
        if let chairAfter, chairAfter != chairBefore {
            sentences.append("\(chairAfter) is now the chair.")
        }
        return sentences.isEmpty ? "The board's members are unchanged." : sentences.joined(separator: " ")
    }

    public static func linked(_ adult: String, to youth: String) -> String {
        "\(adult) is linked to \(youth)."
    }

    public static func unlinked(_ adult: String, from youth: String) -> String {
        "\(adult) is no longer linked to \(youth)."
    }

    /// One adult by name, several by how many. Empty for no one.
    public static func markedGoneHome(_ names: [String]) -> String {
        adults(names, "is marked gone home.", "are marked gone home.")
    }

    public static func markedBack(_ names: [String]) -> String {
        adults(names, "is marked back.", "are marked back.")
    }

    /// Signed in on the Mac, by Add Adult or from the adult history.
    public static func signedIn(_ names: [String]) -> String {
        adults(names, "is signed in for today.", "are signed in for today.")
    }

    public static func roomAdded(_ room: String) -> String {
        "Room \(room) added."
    }

    public static func roomsCopied(_ count: Int, from event: String, locale: Locale = .current) -> String {
        "\(Count.of(count, "room", "rooms")) copied from \(Timestamp.shownDate(event, locale: locale))."
    }

    public static func roomRemoved(_ room: String) -> String {
        "Room \(room) removed."
    }

    public static func roomRenamed(_ old: String, to new: String) -> String {
        "Room \(old) is now room \(new)."
    }

    public static func roomUse(_ room: String, _ boardType: BoardType) -> String {
        "Room \(room) is now for \(boardType.label)s."
    }

    /// Move Board, from who was in each room before the move.
    public static func boardMoved(from first: String, holding firstYouth: String?, to second: String, holding secondYouth: String?) -> String {
        switch (firstYouth, secondYouth) {
        case (.some, .some): "The boards in rooms \(first) and \(second) swapped rooms."
        case (.some(let youth), nil): "\(youth)'s board moved to room \(second)."
        case (nil, .some(let youth)): "\(youth)'s board moved to room \(first)."
        case (nil, nil): "Rooms \(first) and \(second) are both free."
        }
    }

    /// Edit › Undo and Redo, by the step's name in the Edit menu.
    public static func undid(_ step: String) -> String { "Undid \(step)." }
    public static func redid(_ step: String) -> String { "Redid \(step)." }

    private static func adults(_ names: [String], _ one: String, _ many: String) -> String {
        switch names.count {
        case 0: ""
        case 1: "\(names[0]) \(one)"
        default: "\(Count.of(names.count, "adult", "adults")) \(many)"
        }
    }

    /// "Ann", "Ann and Bob", "Ann, Bob, and Cy".
    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
    }
}

/// Who signed in at the tablet since the last time it was said, in one
/// sentence however many came: never one per person during the rush.
public enum Arrivals {
    public static func sentence(youth: [String], adults: [String]) -> String {
        switch (youth.count, adults.count) {
        case (0, 0): ""
        case (1, 0): "\(youth[0]) signed in."
        case (0, 1): "\(adults[0]) signed in."
        case (_, 0): "\(Count.of(youth.count, "youth", "youth")) signed in."
        case (0, _): "\(Count.of(adults.count, "adult", "adults")) signed in."
        default: "\(Count.of(youth.count, "youth", "youth")) and \(Count.of(adults.count, "adult", "adults")) signed in."
        }
    }
}

/// How many rows a search leaves, said once typing pauses.
public enum SearchSpeech {
    /// "40 records", or "12 of 40 records" while a search hides some.
    public static func tableCount(shown: Int, total: Int) -> String {
        let records = Count.of(total, "record", "records")
        return shown == total ? records : "\(shown) of \(records)"
    }

    /// Add Adult's search of the adult history, which lists `shown` of the
    /// `total` it found.
    public static func historyFound(total: Int, shown: Int) -> String {
        switch total {
        case 0: "No one in the adult history matches."
        case 1: "1 adult found."
        case _ where total > shown:
            "\(Count.of(total, "adult", "adults")) found, the first \(shown) shown. Type more of the name to narrow them down."
        default: "\(Count.of(total, "adult", "adults")) found."
        }
    }
}

/// A room going from on time to running long or overdue, said once, as the
/// card's tint would be seen in passing.
public enum RoomTimerSpeech {
    /// Each sitting board's timer, by youth, status and the time of its last
    /// step, so a board seated again starts afresh.
    public typealias States = [String: RoomTimer.State]

    /// Also what the overdue notification is keyed by, so each is sent once.
    public static func key(for youth: Scout) -> String {
        "\(youth.id)|\(youth.statusText)|\(youth.lastUpdateTime)"
    }

    /// The timers now, and every room that turned since `previous`, in one
    /// announcement. Nil `previous` is the first look after an event opens:
    /// it only records, so opening an event does not read out every room. A
    /// board not seen before counts as on time.
    public static func check(previous: States?, youth: [Scout], config: Config, now: Date) -> (states: States, spoken: String) {
        var states: States = [:]
        var turned: [String] = []
        for youth in youth where youth.status?.holdsRoom == true {
            guard let minutes = youth.minutesSinceLastUpdate(now: now),
                  let state = RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: minutes, config: config)
            else { continue }
            let key = key(for: youth)
            states[key] = state
            guard let previous, state != previous[key] ?? .okay else { continue }
            switch state {
            case .warning: turned.append("Room \(youth.room) is running long: \(youth.shownFullName), \(Count.minutes(minutes)).")
            case .overdue: turned.append("Room \(youth.room) is overdue: \(youth.shownFullName), \(Count.minutes(minutes)).")
            case .okay: break
            }
        }
        return (states, turned.joined(separator: " "))
    }
}

extension String {
    /// " · " read as a pause: "W9 · Troop 1409 · Final Board" is shown with
    /// its dots and read "W9, Troop 1409, Final Board", whatever VoiceOver's
    /// punctuation setting does with a middle dot.
    public var spokenList: String {
        replacingOccurrences(of: " · ", with: ", ")
    }

    /// A list of names as the data files keep it, comma- or `~`-separated,
    /// one name each.
    public var memberLines: [String] {
        split(whereSeparator: { $0 == "," || $0 == "~" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

extension Scout {
    /// How long since their last step, in words: "Waiting 12 minutes",
    /// "Board convening for 12 minutes", "In review for 12 minutes",
    /// "Finished 12 minutes ago".
    public func timeText(minutes: Int) -> String {
        switch status {
        case .seated: "Board convening for \(Count.minutes(minutes))"
        case .inProgress: "In review for \(Count.minutes(minutes))"
        case .completed, .postponed: "Finished \(Count.minutes(minutes)) ago"
        default: "Waiting \(Count.minutes(minutes))"
        }
    }

    /// Their row in the youth list as VoiceOver reads it, after the name:
    /// where they are in words, then what the second line shows, with
    /// commas for its dots and the unit and board type in full.
    /// "Waiting 12 minutes, W9, Troop 1409, Proposal Review";
    /// "In review for 31 minutes, running long, W2, Troop 1409, Room 101";
    /// "Completed, Approved, P1, Troop 1409, Final Board".
    public func queueValue(minutes: Int?, timer: RoomTimer.State?) -> String {
        var place: [String]
        switch status {
        case .seated:
            place = [minutes.map { "Seated, convening for \(Count.minutes($0))" } ?? "Seated"]
        case .inProgress:
            place = [minutes.map { "In review for \(Count.minutes($0))" } ?? "In review"]
        case .completed, .postponed:
            place = [status?.label ?? statusText]
            if status == .completed, let ended = BoardResult(rawValue: self.result) {
                place.append(ended.label)
            }
        case .registered, .verified, nil:
            place = [minutes.map { "Waiting \(Count.minutes($0))" } ?? "Waiting"]
        }
        if status?.holdsRoom == true {
            switch timer {
            case .warning: place.append("running long")
            case .overdue: place.append("overdue")
            case .okay, nil: break
            }
        }
        let board = status?.holdsRoom == true ? "Room \(room)" : boardType?.label ?? boardTypeText
        return (place + [regNum, unitDisplay, board]).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The row's help: how long, then what the sign-in number means.
    public func queueHelp(minutes: Int?) -> String {
        [minutes.map { timeText(minutes: $0) + "." } ?? "", regNumHelp].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension Room {
    /// A room card as VoiceOver reads it, with its members named as members:
    /// "Room 101, Final Board, Jane Doe, Seated, 12 minutes, running long,
    /// members Bob Smith, Ann Lee", or "Room 101, Final Board, free". The
    /// minutes are there when the card shows its timer.
    public func spokenLabel(occupant: Scout?, minutes: Int?, timer: RoomTimer.State?) -> String {
        var parts = ["Room \(name)", boardType?.label ?? boardTypeText]
        guard !isFree else { return (parts + ["free"]).filter { !$0.isEmpty }.joined(separator: ", ") }
        parts.append(scoutName.shownValue)
        if let status = occupant?.status { parts.append(status.label) }
        if let minutes, let timer {
            parts.append(Count.minutes(minutes))
            switch timer {
            case .warning: parts.append("running long")
            case .overdue: parts.append("overdue")
            case .okay: break
            }
        }
        let members = leaderNames.memberLines
        if !members.isEmpty {
            parts.append("\(members.count == 1 ? "member" : "members") \(members.joined(separator: ", "))")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension BoardRole {
    /// The role as the rows and role menus show it: No Thanks for Unavailable.
    public var label: String { self == .unavailable ? "No Thanks" : rawValue }
}

extension Adult {
    /// An adult's row beside a board, read as one element in the order it
    /// shows: "Bob Smith, Wood Badge, Same unit, Troop 1409, Chair". `place`
    /// is the unit the row shows, or why they cannot sit ("Gone home");
    /// `role` the role it shows. The add or remove button is read on its own.
    public func spokenRow(youth: Scout?, place: String, role: String) -> String {
        let sameUnit = youth.map { !BoardRules.unitConflicts(scoutUnitName: $0.unitName, members: [self]).isEmpty } ?? false
        return [shownFullName, woodBadge == "Y" ? "Wood Badge" : "", sameUnit ? "Same unit" : "", place, role]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
