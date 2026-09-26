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
    let night: EventNight
    let scoutID: String

    @State private var roomID: String?
    @State private var chairID: String?
    @State private var acknowledged: Set<String> = []

    var body: some View {
        if let youth = night.scout(id: scoutID) {
            let members = model.draftMembers(for: scoutID)
            let room = roomID.flatMap { night.room(id: $0) }
            let review = SeatingReview(scout: youth, members: members, room: room)
            let chairIsQualified = review.qualifiedChairs.contains { $0.id == chairID }
            let warningsCleared = review.warnings.allSatisfy { acknowledged.contains($0.id) }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seat \(youth.fullName)'s Board").font(.headline)
                    Text("The members get the room and the paperwork. \(youth.first) waits outside until Start Review.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                Form {
                    Section {
                        LabeledContent("Youth", value: youth.fullName)
                        LabeledContent("Unit", value: youth.unitName)
                        LabeledContent("Board", value: youth.boardType?.label ?? youth.boardTypeText)
                        if !youth.leader.isEmpty {
                            LabeledContent("Leader", value: youth.leader)
                        }
                    }

                    Section {
                        Picker("Room", selection: $roomID) {
                            Text("Choose a room").tag(String?.none)
                            ForEach(roomChoices) { choice in
                                Text(roomLabel(choice)).tag(Optional(choice.id))
                            }
                        }
                    }

                    Section {
                        if members.isEmpty {
                            Text("No one is checked yet.").foregroundStyle(.secondary)
                        }
                        ForEach(members) { member in
                            HStack {
                                Text(member.fullName)
                                AdultMarks(adult: member, youth: youth)
                                Spacer()
                                Text(member.unitLabel).foregroundStyle(.secondary)
                                RoleText(role: youth.boardType.flatMap { member.role(for: $0)?.rawValue } ?? "")
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    } header: {
                        Text("Board members (\(members.count))")
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
                                Text(chair.fullName).tag(Optional(chair.id))
                            }
                        }
                        .disabled(review.qualifiedChairs.isEmpty)
                    } footer: {
                        Text("Only members whose \(youth.boardType == .projectReview ? "Project" : "Final") role is Chair may chair.")
                            .foregroundStyle(.secondary)
                    }

                    if !review.blockingProblems.isEmpty {
                        Section("Cannot seat yet") {
                            ForEach(review.blockingProblems, id: \.self) { problem in
                                Label(problem, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if !review.warnings.isEmpty {
                        Section("Check before seating") {
                            ForEach(review.warnings) { warning in
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(warning.title, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
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
                        }
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Seat Board") {
                        guard let roomID, let chairID else { return }
                        if model.seat(scoutID: youth.id, roomID: roomID, chairID: chairID, memberIDs: members.map(\.id)) {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!review.canSeat || !chairIsQualified || !warningsCleared)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(width: 560, height: 640)
            .onAppear {
                roomID = model.drafts[scoutID]?.roomID
                    ?? night.rooms.first { $0.isFree && $0.boardType == youth.boardType }?.id
                chairID = review.qualifiedChairs.first?.id
            }
            .onChange(of: review.qualifiedChairs.map(\.id)) { _, chairs in
                if !chairs.contains(where: { $0 == chairID }) {
                    chairID = chairs.first
                }
            }
        } else {
            ContentUnavailableView("That youth is no longer on the list", systemImage: "person.crop.circle.badge.xmark")
                .frame(width: 420, height: 240)
        }
    }

    /// Free rooms first, then the rest, so the list reads as a choice.
    private var roomChoices: [Room] {
        night.rooms.filter(\.isFree) + night.rooms.filter { !$0.isFree }
    }

    private func roomLabel(_ room: Room) -> String {
        let kind = room.boardType?.label ?? room.boardTypeText
        return room.isFree ? "\(room.name) -- \(kind)" : "\(room.name) -- \(kind), in use by \(room.scoutName)"
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
                Text(title).font(.headline)
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
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                buttons
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: width)
    }
}

/// Complete: record the result. The room and the members are freed.
struct CompleteBoardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let night: EventNight
    let scoutID: String

    @State private var result: BoardResult = .approved
    @State private var notes = ""

    var body: some View {
        let youth = night.scout(id: scoutID)
        SheetLayout(
            title: "Complete \(youth.map { "\($0.fullName)'s" } ?? "the") Board",
            message: youth.map {
                "Room \($0.room) · \($0.boardType?.label ?? $0.boardTypeText) · chaired by \($0.boardChair). "
                    + "The room and the members are freed for the next board."
            }
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
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Complete") {
                if model.complete(scoutID: scoutID, result: result, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(youth?.status != .inProgress)
        }
    }
}

struct AddRoomSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let night: EventNight

    @State private var name = ""
    @State private var boardType: BoardType = .finalBoard
    @State private var problem: String?

    var body: some View {
        SheetLayout(
            title: "Add a Room",
            message: "Mark it by what it is used for today, not by what it is called. "
                + "To hold two proposal reviews in one room, add it twice, e.g. 200A and 200B."
        ) {
            Section {
                TextField("Name", text: $name, prompt: Text("101 or 200A"))
                Picker("Used for", selection: $boardType) {
                    ForEach(BoardType.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(.red)
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
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

/// Rename a room. A board in it moves with it: its youth and adults follow
/// the new name, and its timer keeps running.
struct RenameRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    let night: EventNight
    let roomID: String
    /// Does the rename and returns the room's new ID, which changes with its
    /// name. The scheduler's makes it undoable.
    var rename: ((String) throws -> String)?
    /// Called with the room's new ID.
    var onRenamed: (String) -> Void = { _ in }

    @State private var name = ""
    @State private var problem: String?

    var body: some View {
        let room = night.room(id: roomID)
        SheetLayout(
            title: "Rename Room \(room?.name ?? "")",
            message: room.flatMap { $0.isFree ? nil : "\($0.scoutName)'s board is in this room. It moves with the new name; nobody has to be reseated." }
        ) {
            Section {
                TextField("New name", text: $name, prompt: Text("101 or 200A"))
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(.red)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Rename") {
                do {
                    onRenamed(try rename?(name) ?? night.renameRoom(id: roomID, to: name))
                    dismiss()
                } catch {
                    problem = error.localizedDescription
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == room?.name)
        }
        .onAppear { name = room?.name ?? "" }
    }
}

struct SwapRoomsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let night: EventNight
    let firstRoomID: String

    @State private var secondRoomID: String?
    @State private var mixedTypesConfirmed = false

    var body: some View {
        let first = night.room(id: firstRoomID)
        let second = secondRoomID.flatMap { night.room(id: $0) }
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
                    ForEach(night.rooms.filter { $0.id != firstRoomID }) { room in
                        Text(describe(room)).tag(Optional(room.id))
                    }
                }
                if mixedTypes, let first, let second {
                    Toggle("Room \(first.name) is for \(first.boardType?.label ?? "?") and room \(second.name) is for "
                        + "\(second.boardType?.label ?? "?"). Move anyway", isOn: $mixedTypesConfirmed)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(second?.isFree == false ? "Swap" : "Move") {
                guard let secondRoomID else { return }
                if model.swapRooms(firstRoomID, secondRoomID) {
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(second == nil || (mixedTypes && !mixedTypesConfirmed))
        }
    }

    private func describe(_ room: Room) -> String {
        room.isFree ? "\(room.name) (free)" : "\(room.name) (\(room.scoutName))"
    }
}

/// Open another event, for its records or its report.
struct OpenNightSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?

    var body: some View {
        SheetLayout(
            title: "Open Another Event",
            message: "The sign-in station serves whichever event is open."
        ) {
            Section {
                Picker("Event", selection: $chosen) {
                    ForEach(eventsOnFile, id: \.self) { name in
                        Text(name == model.today ? "\(name) (today)" : name).tag(Optional(name))
                    }
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Open") {
                if let chosen, let folder = model.dataFolder {
                    model.open(folder: folder, night: chosen)
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(chosen == nil || chosen == model.night?.night)
        }
        .onAppear { chosen = model.night?.night }
    }

    /// Newest first, with today even before it has a folder.
    private var eventsOnFile: [String] {
        let onFile = (model.dataFolder?.nights() ?? []).sorted(by: >)
        return onFile.contains(model.today) ? onFile : [model.today] + onFile
    }
}
