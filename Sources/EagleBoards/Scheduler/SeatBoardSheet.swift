import EagleBoardsCore
import SwiftUI

/// Seat Board: everything to check before a board convenes, in one place.
///
/// Problems that make the board impossible are listed together, so a board
/// with several issues does not have to be fixed one alert at a time. Things
/// that are legal but unusual -- a same-unit member, a fourth member, a room
/// of the other kind -- each need their own tick before Seat Board is enabled.
/// The chair can only be someone qualified to chair this kind of board.
struct SeatBoardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: BoardEvent
    let scoutID: String

    @State private var roomID: String?
    @State private var chairID: String?
    @State private var acknowledged: Set<String> = []
    @State private var problem: String?

    var body: some View {
        if let youth = event.scout(id: scoutID) {
            let members = model.draftMembers(for: scoutID)
            let room = roomID.flatMap { event.room(id: $0) }
            let review = SeatingReview(scout: youth, members: members, room: room)
            let chairIsQualified = review.qualifiedChairs.contains { $0.id == chairID }
            let warningsCleared = review.warnings.allSatisfy { acknowledged.contains($0.id) }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seat \(youth.shownFullName)'s Board").font(.headline).heading(.h1)
                    Text("The members get the room and the paperwork. \(youth.first.shownValue) waits outside until Start Review.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                Form {
                    Section {
                        LabeledContent("Youth", value: youth.shownFullName)
                        LabeledContent("Unit", value: youth.unitDisplay)
                        LabeledContent("Board", value: youth.boardType?.label ?? youth.boardTypeText)
                        if !youth.leader.isEmpty {
                            LabeledContent("Leader", value: youth.leader.shownValue)
                        }
                    }

                    Section {
                        Picker("Room", selection: $roomID) {
                            Text("Choose a Room").tag(String?.none)
                            ForEach(roomChoices) { choice in
                                Text(roomLabel(choice)).accessibilityLabel(roomLabel(choice).spokenList).tag(Optional(choice.id))
                            }
                        }
                    }

                    Section {
                        if members.isEmpty {
                            Text("No one is checked yet.").foregroundStyle(.secondary)
                        }
                        ForEach(members) { member in
                            let role = youth.boardType.flatMap { member.role(for: $0) }
                            HStack {
                                Text(member.shownFullName)
                                AdultMarks(adult: member, youth: youth)
                                Spacer()
                                Text(member.unitDisplay).foregroundStyle(.secondary)
                                RoleText(role: role?.rawValue ?? "")
                                    .frame(width: 72, alignment: .trailing)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(member.spokenRow(youth: youth, place: member.unitDisplay, role: role?.label ?? ""))
                        }
                    } header: {
                        Text("Board members (\(members.count))").heading(.h2)
                    } footer: {
                        Text("Change who sits on the board in the inspector.")
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Picker("Chair", selection: $chairID) {
                            if review.qualifiedChairs.isEmpty {
                                Text("No qualified chair selected").tag(String?.none)
                            }
                            ForEach(review.qualifiedChairs) { chair in
                                Text(chair.shownFullName).tag(Optional(chair.id))
                            }
                        }
                        .disabled(review.qualifiedChairs.isEmpty)
                    } footer: {
                        Text(SeatingReview.whoMayChair(youth.boardType ?? .finalBoard))
                            .foregroundStyle(.secondary)
                    }

                    if !review.blockingProblems.isEmpty {
                        Section {
                            ForEach(review.blockingProblems, id: \.self) { problem in
                                NoticeLabel.problem(problem)
                            }
                        } header: {
                            Text("Cannot seat yet").heading(.h2)
                        }
                    }

                    if !review.warnings.isEmpty {
                        Section {
                            ForEach(review.warnings) { warning in
                                VStack(alignment: .leading, spacing: 4) {
                                    NoticeLabel.warning(warning.title)
                                        .font(.headline)
                                    Text(warning.detail).fixedSize(horizontal: false, vertical: true)
                                    Toggle("Seat anyway", isOn: Binding(
                                        get: { acknowledged.contains(warning.id) },
                                        set: { isOn in
                                            if isOn { acknowledged.insert(warning.id) } else { acknowledged.remove(warning.id) }
                                        }
                                    ))
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("Check before seating").heading(.h2)
                        }
                    }
                }
                .formStyle(.grouped)

                VStack(alignment: .leading, spacing: 10) {
                    if let problem {
                        SheetProblem(text: problem)
                    }
                    HStack {
                        Spacer()
                        Button("Cancel", role: .cancel) { dismiss() }
                            .keyboardShortcut(.cancelAction)
                        Button("Seat Board") {
                            guard let roomID, let chairID else { return }
                            do {
                                try model.seat(scoutID: youth.id, roomID: roomID, chairID: chairID, memberIDs: members.map(\.id))
                                dismiss()
                            } catch {
                                problem = error.localizedDescription
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!review.canSeat || !chairIsQualified || !warningsCleared)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .boardSheetFrame()
            .onAppear {
                roomID = model.drafts[scoutID]?.roomID
                    ?? event.rooms.first { $0.isFree && $0.boardType == youth.boardType }?.id
                chairID = model.drafts[scoutID]?.chairToSeat(from: review.qualifiedChairs) ?? review.qualifiedChairs.first?.id
            }
            .onChange(of: review.qualifiedChairs.map(\.id)) { _, chairs in
                if !chairs.contains(where: { $0 == chairID }) {
                    chairID = chairs.first
                }
            }
            // A refusal is about the room and chair it was given.
            .onChange(of: [roomID, chairID]) { problem = nil }
        } else {
            SheetUnavailable(title: "That Youth Is No Longer on the List", text: "Nothing was seated.")
        }
    }

    /// Free rooms first, then the rest, so the list reads as a choice.
    private var roomChoices: [Room] {
        event.rooms.filter(\.isFree) + event.rooms.filter { !$0.isFree }
    }

    private func roomLabel(_ room: Room) -> String {
        let kind = room.boardType?.label ?? room.boardTypeText
        return room.isFree ? "\(room.name) · \(kind)" : "\(room.name) · \(kind) · in use by \(room.scoutName.shownValue)"
    }
}

/// The frame the small sheets share, after the sheets in Apple's own apps:
/// a bold title and a line on what it does, the fields grouped, and the
/// buttons at the bottom right with the default one last.
struct SheetLayout<Fields: View, Buttons: View>: View {
    let title: String
    var message: String?
    var width: CGFloat = 440
    @ViewBuilder var fields: Fields
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).heading(.h1)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Form { fields }
                .formStyle(.grouped)

            HStack {
                Spacer()
                buttons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: width)
        // As tall as the fields need, until the screen runs out: then they
        // scroll, and the buttons stay in view.
        .frame(maxHeight: SheetHeight.available)
    }
}

/// How tall a sheet can be on the scheduler's screen. It hangs below the
/// window's toolbar, so at a low scaled resolution a tall sheet would run off
/// the bottom of the screen, its buttons with it.
@MainActor
enum SheetHeight {
    static var available: CGFloat {
        let app = NSApplication.shared
        let screen = app.keyWindow?.screen ?? app.mainWindow?.screen ?? NSScreen.main
        // Room for the title bar and toolbar above the sheet.
        return max(240, (screen?.visibleFrame.height ?? 800) - 80)
    }
}

extension View {
    /// Seat Board's and Change Members' size: 640 points tall where the
    /// screen has room, shorter where it does not, with the form scrolling.
    func boardSheetFrame() -> some View {
        let available = SheetHeight.available
        return frame(width: 560)
            .frame(minHeight: min(400, available), idealHeight: min(640, available), maxHeight: available)
    }
}

/// What Seat Board or Change Members shows when its youth is gone, or has
/// no board type: why, and the way out.
struct SheetUnavailable: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text(text)
        } actions: {
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 420, height: 240)
    }
}

/// Complete: record the result. The room and the members are freed.
struct CompleteBoardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: BoardEvent
    let scoutID: String

    @State private var result: BoardResult = .approved
    @State private var notes = ""
    @State private var problem: String?

    var body: some View {
        let youth = event.scout(id: scoutID)
        let message = youth.map {
            "Room \($0.room), \($0.boardType?.label ?? $0.boardTypeText), chaired by \($0.boardChair.shownValue). "
                + "The room and the members are freed for the next board."
        }
        SheetLayout(
            title: "Complete \(youth.map { "\($0.shownFullName)'s" } ?? "the") Board",
            message: message
        ) {
            Section {
                Picker("Result", selection: $result) {
                    ForEach(BoardResult.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.radioGroup)
                TextField("Notes", text: $notes, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(3...8)
            } footer: {
                if let problem {
                    SheetProblem(text: problem)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Complete") {
                do {
                    try model.complete(scoutID: scoutID, result: result, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                } catch {
                    problem = error.localizedDescription
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(youth?.status != .inProgress)
        }
        .onChange(of: result) { problem = nil }
    }
}

struct AddRoomSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: BoardEvent

    @State private var name = ""
    @State private var boardType: BoardType = .finalBoard
    @State private var problem: String?
    /// The name is what a refusal is about, so the cursor goes back to it.
    @FocusState private var nameFocused: Bool

    var body: some View {
        SheetLayout(
            title: "Add a Room",
            message: "Mark it by what it is used for today, not by what it is called. "
                + "To hold two proposal reviews in one room, add it twice, for example 200A and 200B."
        ) {
            Section {
                TextField("Name", text: $name, prompt: Text("101 or 200A"))
                    .focused($nameFocused)
                Picker("Used for", selection: $boardType) {
                    ForEach(BoardType.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                if let problem {
                    SheetProblem(text: problem)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Add Room") {
                do {
                    try model.addRoom(named: name, boardType: boardType)
                    dismiss()
                } catch {
                    problem = error.localizedDescription
                    refocusName($nameFocused)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // A turn later, once the sheet is in its window.
        .onAppear { Task { nameFocused = true } }
    }
}

/// Put the cursor back in a room sheet's name, with its text selected, so
/// the fix for a refusal is typed straight over it, as Windows' dialogs do.
/// Out and back in, a turn apart: a field that still has the cursor, after
/// Return, would otherwise not take it again, and keep its text unselected.
@MainActor
private func refocusName(_ focused: FocusState<Bool>.Binding) {
    focused.wrappedValue = false
    Task { focused.wrappedValue = true }
}

/// Rename a room. A board in it moves with it: its youth and adults follow
/// the new name, and its timer keeps running.
struct RenameRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: BoardEvent
    let roomID: String
    /// Does the rename, undoably. The room keeps its ID.
    let rename: (String) throws -> Void

    @State private var name = ""
    @State private var problem: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        let room = event.room(id: roomID)
        SheetLayout(
            title: "Rename Room \(room?.name ?? "")",
            message: room.flatMap { $0.isFree ? nil : "\($0.scoutName.shownValue)'s board is in this room. It moves with the new name; nobody has to be reseated." }
        ) {
            Section {
                TextField("New name", text: $name, prompt: Text("101 or 200A"))
                    .focused($nameFocused)
            } footer: {
                if let problem {
                    SheetProblem(text: problem)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Rename") {
                do {
                    try rename(name)
                    dismiss()
                } catch {
                    problem = error.localizedDescription
                    refocusName($nameFocused)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == room?.name)
        }
        .onAppear {
            name = room?.name ?? ""
            // Once the old name is in, so it is selected and typing replaces it.
            Task { nameFocused = true }
        }
    }
}

struct SwapRoomsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: BoardEvent
    let firstRoomID: String

    @State private var secondRoomID: String?
    @State private var mixedTypesConfirmed = false
    @State private var problem: String?

    var body: some View {
        let first = event.room(id: firstRoomID)
        let second = secondRoomID.flatMap { event.room(id: $0) }
        let mixedTypes = first != nil && second != nil && first?.boardType != second?.boardType

        SheetLayout(
            title: "Move the Board in Room \(first?.name ?? "")",
            message: "Everything moves: the youth, the board members and the room card. "
                + "Choosing a room with a board in it swaps the two."
        ) {
            Section {
                LabeledContent("From", value: first.map(describe) ?? firstRoomID)
                Picker("To", selection: $secondRoomID) {
                    Text("Choose a Room").tag(String?.none)
                    ForEach(event.rooms.filter { $0.id != firstRoomID }) { room in
                        Text(describe(room)).tag(Optional(room.id))
                    }
                }
                if mixedTypes, let first, let second {
                    Toggle("Room \(first.name) is for \(first.boardType?.label ?? "?") and room \(second.name) is for "
                        + "\(second.boardType?.label ?? "?"). Move anyway", isOn: $mixedTypesConfirmed)
                }
            } footer: {
                if let problem {
                    SheetProblem(text: problem)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(second?.isFree == false ? "Swap" : "Move") {
                guard let secondRoomID else { return }
                do {
                    try model.swapRooms(firstRoomID, secondRoomID)
                    dismiss()
                } catch {
                    problem = error.localizedDescription
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(second == nil || (mixedTypes && !mixedTypesConfirmed))
        }
        .onChange(of: secondRoomID) { problem = nil }
    }

    private func describe(_ room: Room) -> String {
        room.isFree ? "\(room.name) (free)" : "\(room.name) (\(room.scoutName.shownValue))"
    }
}

/// Open another event, for its records or its report.
struct OpenEventSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?
    @State private var problem: String?

    var body: some View {
        SheetLayout(
            title: "Open Another Event",
            message: "The sign-in station serves whichever event is open."
        ) {
            Section {
                Picker("Event", selection: $chosen) {
                    ForEach(eventsOnFile, id: \.self) { name in
                        Text(DataFolder.eventLabel(name, today: model.today)).help(name).tag(Optional(name))
                    }
                }
            } footer: {
                if let problem {
                    SheetProblem(text: problem)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Open") {
                guard let chosen, let folder = model.dataFolder else { return }
                // A failure stays in the sheet, to choose another event.
                do {
                    try model.openOrThrow(folder: folder, event: chosen)
                    dismiss()
                } catch {
                    problem = DataFolder.openFailed(chosen, reason: error.localizedDescription)
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(chosen == nil || chosen == model.event?.date)
        }
        .onAppear { chosen = model.event?.date }
        .onChange(of: chosen) { problem = nil }
    }

    /// Newest first, with today even before it has a folder.
    private var eventsOnFile: [String] {
        let onFile = (model.dataFolder?.events() ?? []).sorted(by: >)
        return onFile.contains(model.today) ? onFile : [model.today] + onFile
    }
}
