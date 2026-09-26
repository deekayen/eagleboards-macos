import EagleBoardsCore
import SwiftUI

/// The operator's screen for the evening. The sidebar picks a list -- youth
/// waiting, on boards or finished, the adults, or the rooms -- and the
/// inspector follows the selected youth: the board being drawn up for them,
/// or how it went.
///
/// Nothing here polls. The event night is observed directly, so a youth who
/// signs in at the door appears the moment the tablet's request lands.
struct SchedulerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    let night: EventNight

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SchedulerSidebar(night: night)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            content
                .navigationTitle(title)
                .navigationSubtitle(nightSubtitle)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: searchPrompt)
        .inspector(isPresented: $model.showsInspector) {
            YouthInspector(night: night)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
                .toolbar {
                    ToolbarItem {
                        Button {
                            model.showsInspector.toggle()
                        } label: {
                            Label("Inspector", systemImage: "sidebar.trailing")
                        }
                        .help("Show or hide the selected youth's board")
                    }
                }
        }
        .toolbar { toolbar }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .seatBoard(let scoutID): SeatBoardSheet(night: night, scoutID: scoutID)
            case .changeMembers(let scoutID): ChangeMembersSheet(night: night, scoutID: scoutID)
            case .completeBoard(let scoutID): CompleteBoardSheet(night: night, scoutID: scoutID)
            case .addRoom: AddRoomSheet(night: night)
            case .swapRooms(let roomID): SwapRoomsSheet(night: night, firstRoomID: roomID)
            case .renameRoom(let roomID):
                RenameRoomSheet(night: night, roomID: roomID, rename: { try model.renameRoom(roomID, to: $0) })
            case .openNight: OpenNightSheet()
            }
        }
        .confirmationDialog(
            model.confirmation?.title ?? "",
            isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }),
            presenting: model.confirmation
        ) { confirmation in
            Button(confirmation.actionTitle, role: confirmation.isDestructive ? .destructive : nil) {
                confirmation.action()
            }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
        .messageAlert()
        .onChange(of: proposalInputs) { model.refreshProposals() }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: model.waitingCount, initial: true) { model.attention.showWaiting(model.waitingCount) }
        .task(id: night.night) {
            while !Task.isCancelled {
                model.checkRoomTimers()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: undoManager) { model.undoManager = undoManager }
    }

    /// What a proposed board is made from. When any of it changes, proposals
    /// the operator has not touched are made again.
    private var proposalInputs: [String] {
        night.rooms.map { "\($0.id)|\($0.boardTypeText)|\($0.scoutName)" }
            + night.adults.map { "\($0.id)|\($0.room)|\($0.finalBoardRoleText)|\($0.projectReviewRoleText)" }
            + night.scouts.map { "\($0.id)|\($0.statusText)|\($0.boardTypeText)" }
    }

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .waiting, .onBoards, .finished:
            YouthList(night: night, section: model.section)
        case .adults:
            AdultList(night: night)
        case .rooms, .room:
            RoomsGrid(night: night)
        }
    }

    private var title: String {
        switch model.section {
        case .waiting: "Waiting"
        case .onBoards: "On Boards"
        case .finished: "Finished"
        case .adults: "Adults"
        case .rooms, .room: "Rooms"
        }
    }

    private var searchPrompt: String {
        switch model.section {
        case .adults: "Name, unit or room"
        case .rooms, .room: "Room or name"
        default: "Name, unit or leader"
        }
    }

    private var nightSubtitle: String {
        night.night == model.today ? "Today, \(night.night)" : "\(night.night) (an earlier event)"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            CheckInStatusButton()
        }
        ToolbarItem(placement: .primaryAction) {
            NextStepButton()
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                Task { await model.importSignUps() }
            } label: {
                Label("Import Sign-Ups", systemImage: "square.and.arrow.down")
            }
            .help("Import today's pre-registrations and adult sign-ups from SignUpGenius")
            .disabled(model.isImporting)

            Button {
                model.exportReport()
            } label: {
                Label("Export Results", systemImage: "square.and.arrow.up")
            }
            .help("Save every youth's board and result as a spreadsheet (CSV)")

            Button {
                openWindow(id: WindowID.records)
            } label: {
                Label("Records", systemImage: "tablecells")
            }
            .help("View and edit every record: youth, adults, the adult history and rooms")
        }
    }
}

/// The one thing to do next for the selected youth: Seat Board, Start
/// Review or Complete. The same as Command-Return and double-clicking them.
struct NextStepButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let step = model.nextStep
        Button {
            model.performNextStep()
        } label: {
            Label(step?.title ?? BoardStep.seat.title, systemImage: symbol(for: step))
                .labelStyle(.titleAndIcon)
                .fixedSize()
        }
        .disabled(step == nil)
        .help(help(for: step))
    }

    private func symbol(for step: BoardStep?) -> String {
        switch step {
        case .seat: "chair"
        case .startReview: "door.left.hand.open"
        case .complete: "checkmark.seal"
        case nil: "arrow.right.circle"
        }
    }

    private func help(for step: BoardStep?) -> String {
        switch step {
        case .seat: "Put the board members in a room to read the paperwork. The youth waits outside until Start Review."
        case .startReview: "Bring the youth into the room and begin the review, once the members are done reading."
        case .complete: "Finish the review and record the result."
        case nil: "Select a youth who is waiting or on a board"
        }
    }
}

extension View {
    /// Shows the model's message, if any, as an alert titled with what
    /// happened.
    func messageAlert() -> some View {
        modifier(MessageAlert())
    }
}

private struct MessageAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert(
            model.message?.title ?? "",
            isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } }),
            presenting: model.message
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message.text)
        }
    }
}
