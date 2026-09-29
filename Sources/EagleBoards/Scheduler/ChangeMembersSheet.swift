import EagleBoardsCore
import SwiftUI

/// Change who sits on a board that is already Seated or InProgress. The
/// room is fixed to the one the board already holds, and its timer keeps
/// running: this corrects the board already convening or in review, not a
/// new step in its lifecycle.
struct ChangeMembersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: BoardEvent
    let scoutID: String

    @State private var memberIDs: [String] = []
    @State private var chairID: String?
    @State private var acknowledged: Set<String> = []
    @State private var search = ""

    var body: some View {
        if let youth = event.scout(id: scoutID), let boardType = youth.boardType {
            let members = memberIDs.compactMap { event.adult(id: $0) }
            let review = ChangeMembersReview(scout: youth, members: members)
            let chairIsQualified = review.qualifiedChairs.contains { $0.id == chairID }
            let warningsCleared = review.warnings.allSatisfy { acknowledged.contains($0.id) }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Change \(youth.fullName)'s Board Members").font(.headline)
                    Text("Room \(youth.room) keeps its timer; this does not restart it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Form {
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
                                RoleText(role: member.role(for: boardType)?.rawValue ?? "")
                                    .frame(width: 60, alignment: .trailing)
                                Button {
                                    memberIDs.removeAll { $0 == member.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Take \(member.fullName) off this board")
                                .accessibilityLabel("Remove \(member.fullName)")
                            }
                        }
                    } header: {
                        Text("Board members (\(members.count))")
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
                        Text("Only members whose \(boardType == .projectReview ? "Project" : "Final") role is Chair may chair.")
                            .foregroundStyle(.secondary)
                    }

                    if !review.blockingProblems.isEmpty {
                        Section("Cannot save yet") {
                            ForEach(review.blockingProblems, id: \.self) { problem in
                                Label(problem, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if !review.warnings.isEmpty {
                        Section("Check before saving") {
                            ForEach(review.warnings) { warning in
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(warning.title, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.headline)
                                    Text(warning.detail).fixedSize(horizontal: false, vertical: true)
                                    Toggle("Save anyway", isOn: Binding(
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

                    FreeAdultsToAddSection(youth: youth, event: event, boardType: boardType, memberIDs: $memberIDs, search: $search)
                }
                .formStyle(.grouped)

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save Changes") {
                        guard let chairID else { return }
                        if model.changeMembers(scoutID: youth.id, chairID: chairID, memberIDs: memberIDs) {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!review.canApply || !chairIsQualified || !warningsCleared)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(width: 560, height: 640)
            .onAppear {
                memberIDs = youth.boardMemberIDs.split(separator: ",").map(String.init)
                chairID = youth.boardChairID.isEmpty ? nil : youth.boardChairID
            }
            .onChange(of: review.qualifiedChairs.map(\.id)) { _, chairs in
                if !chairs.contains(where: { $0 == chairID }) {
                    chairID = chairs.first
                }
            }
        } else {
            ContentUnavailableView("That youth is no longer on a board", systemImage: "person.crop.circle.badge.xmark")
                .frame(width: 420, height: 240)
        }
    }
}

/// Adults free to join this board, plus its own members not yet checked
/// again after being removed by hand. Click one to add them.
private struct FreeAdultsToAddSection: View {
    let youth: Scout
    let event: BoardEvent
    let boardType: BoardType
    @Binding var memberIDs: [String]
    @Binding var search: String

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let candidates = event.adults
            .filter { ($0.canJoin(boardType) || $0.room == youth.room) && !memberIDs.contains($0.id) }
            .filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query)
                || $0.unitName.localizedCaseInsensitiveContains(query) || $0.unitLabel.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let lhsChairs = lhs.canChair(boardType), rhsChairs = rhs.canChair(boardType)
                if lhsChairs != rhsChairs { return lhsChairs }
                return (lhs.last, lhs.first) < (rhs.last, rhs.first)
            }

        Section("Free for a \(boardType.label) (\(candidates.count))") {
            TextField("Find an adult", text: $search, prompt: Text("Name or unit"))
                .labelsHidden()
            if candidates.isEmpty {
                Text(query.isEmpty ? "Everyone who could sit is on a board." : "No free adult matches.")
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { adult in
                HStack(spacing: 6) {
                    Text(adult.fullName)
                    AdultMarks(adult: adult, youth: youth)
                    Spacer()
                    Text(adult.unitLabel).font(.caption).foregroundStyle(.secondary)
                    RoleText(role: adult.role(for: boardType)?.rawValue ?? "")
                    Button {
                        add(adult)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Put \(adult.fullName) on this board")
                    .accessibilityLabel("Add \(adult.fullName)")
                }
                .contentShape(Rectangle())
                .onTapGesture { add(adult) }
            }
        }
    }

    private func add(_ adult: Adult) {
        memberIDs.append(adult.id)
        search = ""
    }
}
