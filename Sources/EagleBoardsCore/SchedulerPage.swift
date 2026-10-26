/// The scheduler window's pages, in the View menu's order (SPEC.md P-1, P-6),
/// and what each one has in view.
///
/// A command works only on a page that shows what it acts on. The selected
/// youth's board is drawn in the inspector, which sits beside the Event page
/// alone, so the board's steps and members are for that page; the rooms are
/// the Event page's cards and the Rooms page's table; the event's adults are
/// the Adults page's table. A selection made on one page is kept for when the
/// operator comes back to it, but it is never acted on from a page that cannot
/// show it. Windows' details pane is on its Event page alone, and its Board
/// menu works only there. Edit › Undo and Redo work from every page, so they
/// bring what they changed into view (`revealing(_:)`).
///
/// The questions are here, and not in the views, so each can be tested and a
/// new page has to answer all of them (the switches have no default).
public enum SchedulerPage: Hashable, CaseIterable, Sendable {
    case event
    case results
    case adults
    case youth
    case preRegistered
    case adultHistory
    case rooms
    case approvedProposals

    /// The selected youth's board, in the inspector: the board being drawn
    /// up, the one sitting, or how it went. Every step and change to a board
    /// belongs to this page.
    public var showsBoard: Bool {
        switch self {
        case .event: true
        case .results, .adults, .youth, .preRegistered, .adultHistory, .rooms, .approvedProposals: false
        }
    }

    /// The rooms, as cards or as a table: the Room menu acts on them.
    public var showsRooms: Bool {
        switch self {
        case .event, .rooms: true
        case .results, .adults, .youth, .preRegistered, .adultHistory, .approvedProposals: false
        }
    }

    /// The event's adults, in a table to select from, for Adult › Mark Gone
    /// Home, Mark Back, and Delete.
    public var listsAdults: Bool {
        switch self {
        case .adults: true
        case .event, .results, .youth, .preRegistered, .adultHistory, .rooms, .approvedProposals: false
        }
    }

    /// The adult history, in a table to select from, for Adult › Sign In for
    /// Today.
    public var listsAdultHistory: Bool {
        switch self {
        case .adultHistory: true
        case .event, .results, .adults, .youth, .preRegistered, .rooms, .approvedProposals: false
        }
    }

    /// Whether the page has a row for a youth in this status, so that Board ›
    /// Show on Event Page can take them to where their board is. The Youth
    /// page lists everyone who signed in, whatever the status; Results lists
    /// the boards seated or finished, leaving out those still waiting. The
    /// Event page is where the command goes, so it has nothing to show there.
    /// The Results table filters its rows with this, so the command and the
    /// rows agree.
    public func listsYouth(with status: BoardStatus?) -> Bool {
        switch self {
        case .youth: true
        case .results: status.map { !$0.isWaitingForBoard } ?? false
        case .event, .adults, .preRegistered, .adultHistory, .rooms, .approvedProposals: false
        }
    }

    /// What an undone or redone change was made to, which decides the page
    /// that has it in view.
    public enum Subject: Hashable, CaseIterable, Sendable {
        /// A youth's board: a step, its members, or who introduces them. The
        /// inspector draws all of it.
        case board
        /// A room: added, copied, renamed, moved, removed, or given another use.
        case rooms
        /// The event's adults: marked gone home or back.
        case adults
    }

    /// The page Edit › Undo or Redo of a change to `subject` brings into view
    /// when it is chosen from this page: this page if it has the subject in
    /// view, otherwise the page that does. Undo works from every page, and
    /// without this it would change a board or a room that nothing on the page
    /// shows, with VoiceOver saying it was done.
    ///
    /// A board is the Event page's alone. A room is on the Event page's cards
    /// and the Rooms page's table, so the change stays on either, and any other
    /// page goes to the Event page. The event's adults are the Adults page's.
    /// Linking an adult to a youth as their introducer changes the youth's
    /// With Them list, so it is a `.board` change, not an `.adults` one.
    /// Deleting an adult is not on the Undo stack.
    public func revealing(_ subject: Subject) -> SchedulerPage {
        switch subject {
        case .board: showsBoard ? self : .event
        case .rooms: showsRooms ? self : .event
        case .adults: listsAdults ? self : .adults
        }
    }

    /// Whether the inspector is on screen, given whether the operator wants
    /// it: never where the page has no board to show.
    public func showsInspector(chosen: Bool) -> Bool {
        showsBoard && chosen
    }

    /// The operator's choice to have the inspector, once it reports being
    /// `shown`. The inspector is taken away with a page that has no board, and
    /// SwiftUI reports it closed then; that is not the operator closing it, so
    /// the choice stands until they leave and come back to the Event page.
    public func inspectorChoice(reported shown: Bool, was chosen: Bool) -> Bool {
        showsBoard ? shown : chosen
    }
}
