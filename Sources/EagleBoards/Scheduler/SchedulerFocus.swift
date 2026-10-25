import EagleBoardsCore
import SwiftUI

/// What has the keyboard focus in the scheduler window, where the app moves
/// it itself: into the page shown, from a step's button that went away to the
/// next step's, and along the inspector's lists as their rows come and go.
/// Change Members uses the list cases for its own lists.
enum SchedulerFocus: Hashable {
    case youthList
    /// A table page's table. Never a cell in it: a letter typed with the
    /// table focused selects a row, and would overwrite a focused cell.
    case table(AppModel.Page)
    case seat
    case startReview
    case complete
    case postpone
    case resetBoard
    case clearBoard
    case suggestBoard
    case findAdult
    /// An adult's + button, which puts them on the board.
    case add(Adult.ID)
    /// A member's − button, which takes them off it.
    case remove(Adult.ID)

    /// The page's list or table. Nil for the Adult History CSV and Approved
    /// Proposals, whose AppKit tables take the focus themselves
    /// (`PlainTable.takesFocus`, `AppModel.focusPlainTable`).
    static func content(of page: AppModel.Page) -> SchedulerFocus? {
        switch page {
        case .event: .youthList
        case .results, .adults, .youth, .preRegistered, .rooms: .table(page)
        case .adultHistory, .approvedProposals: nil
        }
    }
}

/// Windows' FocusAfter, for the inspector's step buttons: once a step takes
/// away the button that had the keyboard focus (Seat Board… once the board
/// is seated, say), the focus goes on to the next step's control, or to the
/// youth's row. A step taken any other way, from the youth list, the
/// toolbar, a menu or a click, leaves the focus where it is. With Keyboard
/// navigation off no button takes the focus, so none of this runs.
@MainActor
struct StepFocus {
    /// A step waiting on its sheet or question, which the scheduler lands
    /// when that closes.
    struct Pending {
        let youthID: Scout.ID
        let status: BoardStatus?
        let target: SchedulerFocus
    }

    let model: AppModel
    let focus: FocusState<SchedulerFocus?>.Binding
    let pending: Binding<Pending?>

    /// Take `step` from the button `control`, then focus `target` if the
    /// button had the focus and the step took it away: by default, if the
    /// youth's status changed.
    func run(
        _ control: SchedulerFocus, then target: @autoclosure () -> SchedulerFocus,
        landed: (() -> Bool)? = nil, _ step: () -> Void
    ) {
        let hadFocus = focus.wrappedValue == control
        let youth = model.selectedYouth
        step()
        guard hadFocus, let youth else { return }
        if model.sheet != nil || model.confirmation != nil {
            pending.wrappedValue = Pending(youthID: youth.id, status: youth.status, target: target())
        } else if landed?() ?? (model.event?.scout(id: youth.id)?.status != youth.status) {
            move(to: target())
        }
    }

    func move(to target: SchedulerFocus) {
        // The youth's row is in the youth list on the Event page, and in the
        // page's table elsewhere.
        let resolved = target == .youthList ? SchedulerFocus.content(of: model.page) : target
        guard let resolved else {
            model.focusPlainTable()
            return
        }
        let focus = focus
        // A turn later, once the section holding it is drawn.
        Task { focus.wrappedValue = resolved }
    }
}
