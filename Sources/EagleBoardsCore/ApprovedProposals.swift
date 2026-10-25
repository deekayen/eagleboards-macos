import Foundation

/// A project proposal approved at an earlier event (SPEC.md D-22), for a
/// youth who comes to their board of review without the signed page: who,
/// their unit, when, and by whom. Nothing else from the row, so never a
/// birthdate, phone number or email (D-7, D-8).
public struct ApprovedProposal: Identifiable, Equatable, Sendable {
    public var id: String { "\(event)|\(youthID)" }
    public let youthID: String
    public let first: String
    public let last: String
    public let unit: String
    /// The date of the event that approved it: its folder's name.
    public let event: String
    public let chair: String
    /// The board's other members, the chair left out.
    public let otherMembers: [String]
    public let notes: String

    init(_ youth: Scout, event: String) {
        youthID = youth.id
        first = youth.first.shownValue
        last = youth.last.shownValue
        unit = youth.unitDisplay
        self.event = event
        chair = youth.boardChair.shownValue
        // Split, not read by ID: an earlier event's adults are not loaded, so
        // a name with a comma (D-1) may come apart here.
        otherMembers = youth.boardMembers
            .split(whereSeparator: { $0 == "," || $0 == "~" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != youth.boardChair }
        notes = youth.notes.shownValue
    }
}

/// Every approved proposal from the events before this one, and what was read.
public struct ApprovedProposals: Equatable, Sendable {
    /// Sorted by last name, then first, then the oldest approval first.
    public let approvals: [ApprovedProposal]
    /// The earlier events read, oldest first.
    public let eventsRead: [String]
    /// Earlier events whose youth file could not be read, with why.
    public let unreadable: [Unreadable]

    /// An earlier event whose youth file could not be read.
    public struct Unreadable: Equatable, Sendable {
        /// The event's folder name, `2026-08-25`.
        public let event: String
        public let reason: String

        /// "Could not read the August 25, 2026 event: ...", with the date as
        /// the Mac writes dates.
        public func shownLine(locale: Locale = .current) -> String {
            "Could not read the \(Timestamp.shownDate(event, locale: locale)) event: \(reason)"
        }
    }

    /// The line above the list: how many earlier events were read, from
    /// which date to which, in the Windows version's words
    /// (`EarlierEvents.ApprovedProposals.About`).
    public var summary: String { summary { $0 } }

    /// The same line with its dates as the Mac writes dates, as the page
    /// shows it: "Read from 2 earlier events, May 28, 2019 to August 25, 2026."
    public func shownSummary(locale: Locale = .current) -> String {
        summary { Timestamp.shownDate($0, locale: locale) }
    }

    private func summary(_ date: (String) -> String) -> String {
        guard let first = eventsRead.first, let last = eventsRead.last else {
            return "No earlier events in this data folder."
        }
        return eventsRead.count == 1
            ? "Read from 1 earlier event, \(date(first))."
            : "Read from \(eventsRead.count) earlier events, \(date(first)) to \(date(last))."
    }
}

extension DataFolder {
    /// The approved proposals at every event in this folder dated before
    /// `date`, however long ago (SPEC.md D-22): a project can take more than a
    /// year between its proposal and the board of review. A folder with no
    /// youth file held no event. Read afresh each time; nothing in an
    /// earlier folder is written.
    public func approvedProposals(before date: String) -> ApprovedProposals {
        var approvals: [ApprovedProposal] = []
        var eventsRead: [String] = []
        var unreadable: [ApprovedProposals.Unreadable] = []
        for event in events().filter({ $0 < date }).sorted()
        where FileManager.default.fileExists(atPath: youthURL(event: event).path) {
            do {
                let youth = try CSVFile.read(Scout.self, from: youthURL(event: event))
                eventsRead.append(event)
                approvals += youth
                    .filter { $0.boardType == .projectReview && BoardResult(rawValue: $0.result) == .approved }
                    .map { ApprovedProposal($0, event: event) }
            } catch {
                unreadable.append(.init(event: event, reason: error.localizedDescription))
            }
        }
        approvals.sort {
            let byLast = $0.last.localizedCaseInsensitiveCompare($1.last)
            if byLast != .orderedSame { return byLast == .orderedAscending }
            let byFirst = $0.first.localizedCaseInsensitiveCompare($1.first)
            return byFirst != .orderedSame ? byFirst == .orderedAscending : $0.event < $1.event
        }
        return ApprovedProposals(approvals: approvals, eventsRead: eventsRead, unreadable: unreadable)
    }
}

extension BoardEvent {
    /// The approved proposals from the events before this one: before its
    /// folder's date, or today if the folder isn't named by a date.
    public func approvedProposals() -> ApprovedProposals {
        folder.approvedProposals(before: Timestamp.isDayStamp(date) ? date : Timestamp.dayStamp(for: now))
    }
}
