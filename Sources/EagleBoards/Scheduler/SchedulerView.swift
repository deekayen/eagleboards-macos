import EagleBoardsCore
import SwiftUI

/// The operator's screen for the evening. The View menu chooses the page
/// (SPEC.md P-1, P-6): Event, with every youth in one list beside the rooms,
/// so a room's timer is never out of sight while working the queue (O-3); or
/// a page for one of the event's tables, edited in place -- Results, People,
/// Youth, Pre-Registered, Adult History, Rooms. There is no sidebar and no
/// separate records window, so the page has the window's whole width. The
/// inspector follows the selected youth on every page: the board being drawn
/// up for them, or how it went.
///
/// Nothing here polls. The event night is observed directly, so a youth who
/// signs in at the door appears the moment the tablet's request lands.
struct SchedulerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    /// The youth list's width on the Event page, as the operator last left it.
    @AppStorage("youthListWidth") private var youthListWidth = 320.0
    let night: EventNight

    var body: some View {
        @Bindable var model = model

        content
            .navigationTitle(title)
            .navigationSubtitle(nightSubtitle)
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
                case .addAdult: AddAdultSheet()
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

    /// On the Event page, every youth beside the rooms -- both always on
    /// screen together (O-3). As on Windows, the youth list is a narrow
    /// column and the room cards take the rest of the width, so every room's
    /// board and timer is in view; the divider between them widens the list.
    @ViewBuilder
    private var content: some View {
        switch model.page {
        case .event:
            HStack(spacing: 0) {
                YouthList(night: night)
                    .frame(width: youthListWidth)
                ColumnResizer(width: $youthListWidth, range: 260...520, label: "Youth list width")
                RoomsGrid(night: night)
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            }
        case .results:
            ResultsPage(night: night)
        case .people:
            AdultList(night: night)
        case .youth:
            YouthPage(night: night)
        case .preRegistered:
            PreRegisteredPage(night: night)
        case .adultHistory:
            AdultHistoryPage(night: night)
        case .rooms:
            RoomsPage(night: night)
        }
    }

    private var title: String { model.page.title }

    private var searchPrompt: String {
        switch model.page {
        case .event: "Name, unit, leader or room"
        case .results: "Name, unit, member or result"
        case .people: "Name, unit or room"
        case .youth: "Name, unit, leader or room"
        case .preRegistered: "Name, email, unit or leader"
        case .adultHistory: "Name, email or unit"
        case .rooms: "Room, youth or member"
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
        }
    }
}

/// The line between two columns, dragged to resize the one before it. The
/// grab area is wider than the line, and VoiceOver can adjust it too.
private struct ColumnResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let label: String
    @State private var widthAtDragStart: Double?

    var body: some View {
        Divider()
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    // Global coordinates: the divider moves under the pointer
                    // as it drags, which would skew a local translation.
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            let start = widthAtDragStart ?? width
                            widthAtDragStart = start
                            width = (start + drag.translation.width).clamped(to: range)
                        }
                        .onEnded { _ in widthAtDragStart = nil }
                    )
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = (width + 40).clamped(to: range)
                case .decrement: width = (width - 40).clamped(to: range)
                @unknown default: break
                }
            }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
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
