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
                                if !youth.unitName.isEmpty && member.unitName == youth.unitName {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .help("Same unit as \(youth.fullName)")
                                }
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
                .padding()
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Complete \(youth?.fullName ?? "board")")
                .font(.title2.bold())
            if let youth {
                Text("Room \(youth.room) · \(youth.boardType?.label ?? youth.boardTypeText) · chaired by \(youth.boardChair)")
                    .foregroundStyle(.secondary)
            }
            Picker("Result", selection: $result) {
                ForEach(BoardResult.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.radioGroup)
            Text("Notes").font(.headline)
            TextEditor(text: $notes)
                .font(.body)
                .frame(minHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
            HStack {
                Spacer()
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
        .padding(20)
        .frame(width: 460)
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
        Form {
            TextField("Room", text: $name, prompt: Text("e.g. 101 or 200A"))
            Picker("Used for", selection: $boardType) {
                ForEach(BoardType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Mark rooms by what they are used for tonight, not by what they are called. "
                + "To hold two proposal reviews in one room, add it twice, e.g. 200A and 200B.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
            HStack {
                Spacer()
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
            }
        }
        .padding(20)
        .frame(width: 420)
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
        Form {
            TextField("New name", text: $name, prompt: Text("e.g. 101 or 200A"))
            if let room, !room.isFree {
                Text("\(room.scoutName)'s board is in this room. It moves with the new name; nobody has to be reseated.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                Text(problem).foregroundStyle(.red)
            }
            HStack {
                Spacer()
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
            }
        }
        .padding(20)
        .frame(width: 420)
        .navigationTitle("Rename Room \(room?.name ?? "")")
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

        Form {
            LabeledContent("Room", value: first.map(describe) ?? firstRoomID)
            Picker("Swap with", selection: $secondRoomID) {
                Text("Choose a room").tag(String?.none)
                ForEach(night.rooms.filter { $0.id != firstRoomID }) { room in
                    Text(describe(room)).tag(Optional(room.id))
                }
            }
            Text("Everything moves: the youth, the board members and the room card. Swapping with a free room moves the board.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if mixedTypes, let first, let second {
                Toggle("Room \(first.name) is for \(first.boardType?.label ?? "?") and room \(second.name) is for \(second.boardType?.label ?? "?"). Swap anyway", isOn: $mixedTypesConfirmed)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Swap") {
                    guard let secondRoomID else { return }
                    if model.swapRooms(firstRoomID, secondRoomID) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(second == nil || (mixedTypes && !mixedTypesConfirmed))
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func describe(_ room: Room) -> String {
        room.isFree ? "\(room.name) (free)" : "\(room.name) (\(room.scoutName))"
    }
}

/// Open an earlier night, for its records or its report.
struct OpenNightSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?

    var body: some View {
        let nights = nightsOnFile
        VStack(alignment: .leading, spacing: 12) {
            Text("Open a Night").font(.title2.bold())
            Text("The sign-in station serves whichever night is open.")
                .foregroundStyle(.secondary)
            List(nights, id: \.self, selection: $chosen) { night in
                Text(night == model.today ? "\(night) (tonight)" : night)
            }
            .frame(height: 260)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Open") {
                    if let chosen, let folder = model.dataFolder {
                        model.open(folder: folder, night: chosen)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { chosen = model.night?.night }
    }

    private var nightsOnFile: [String] {
        let onFile = model.dataFolder?.nights() ?? []
        return onFile.contains(model.today) ? onFile : [model.today] + onFile
    }
}
