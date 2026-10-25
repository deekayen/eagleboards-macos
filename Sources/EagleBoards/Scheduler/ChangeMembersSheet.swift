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
    @State private var problem: String?
    /// Find an adult and the + and − buttons, the inspector's cases. While
    /// Find an adult has the cursor, Return adds the first match rather than
    /// pressing Save Changes.
    @FocusState private var focus: SchedulerFocus?

    var body: some View {
        if let youth = event.scout(id: scoutID), let boardType = youth.boardType {
            let members = memberIDs.compactMap { event.adult(id: $0) }
            let review = ChangeMembersReview(scout: youth, members: members)
            let chairIsQualified = review.qualifiedChairs.contains { $0.id == chairID }
            let warningsCleared = review.warnings.allSatisfy { acknowledged.contains($0.id) }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Change \(youth.shownFullName)'s Board Members").font(.headline).heading(.h1)
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
                                // One element for what the row says; the
                                // button stays its own, for Full Keyboard
                                // Access and Voice Control.
                                HStack {
                                    Text(member.shownFullName)
                                    AdultMarks(adult: member, youth: youth)
                                    Spacer()
                                    Text(member.unitDisplay).foregroundStyle(.secondary)
                                    RoleText(role: member.role(for: boardType)?.rawValue ?? "")
                                        .frame(width: 72, alignment: .trailing)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(member.spokenRow(youth: youth, place: member.unitDisplay,
                                                                     role: member.role(for: boardType)?.label ?? ""))
                                Button {
                                    remove(member.id, from: members)
                                } label: {
                                    Image(systemName: "minus.circle").memberButtonTarget()
                                }
                                .focused($focus, equals: .remove(member.id))
                                .buttonStyle(.borderless)
                                .help("Take \(member.shownFullName) off this board")
                                .accessibilityLabel("Remove \(member.shownFullName)")
                            }
                        }
                    } header: {
                        Text("Board members (\(members.count))").heading(.h2)
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
                        Text(SeatingReview.whoMayChair(boardType))
                            .foregroundStyle(.secondary)
                    }

                    if !review.blockingProblems.isEmpty {
                        Section {
                            ForEach(review.blockingProblems, id: \.self) { problem in
                                NoticeLabel.problem(problem)
                            }
                        } header: {
                            Text("Cannot save yet").heading(.h2)
                        }
                    }

                    if !review.warnings.isEmpty {
                        Section {
                            ForEach(review.warnings) { warning in
                                VStack(alignment: .leading, spacing: 4) {
                                    NoticeLabel.warning(warning.title)
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
                        } header: {
                            Text("Check before saving").heading(.h2)
                        }
                    }

                    FreeAdultsToAddSection(youth: youth, event: event, boardType: boardType, memberIDs: $memberIDs,
                                           search: $search, focus: $focus)
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
                        Button("Save Changes") {
                            guard let chairID else { return }
                            do {
                                try model.changeMembers(scoutID: youth.id, chairID: chairID, memberIDs: memberIDs)
                                dismiss()
                            } catch {
                                problem = error.localizedDescription
                            }
                        }
                        .keyboardShortcut(focus == .findAdult ? nil : .defaultAction)
                        .disabled(!review.canApply || !chairIsQualified || !warningsCleared)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .boardSheetFrame()
            .onAppear {
                memberIDs = youth.boardMembers(among: event.adults).members.map(\.id)
                chairID = youth.boardChairID.isEmpty ? nil : youth.boardChairID
            }
            .onChange(of: review.qualifiedChairs.map(\.id)) { _, chairs in
                if !chairs.contains(where: { $0 == chairID }) {
                    chairID = chairs.first
                }
            }
            // A refusal is about the members and chair it was given.
            .onChange(of: memberIDs + [chairID ?? ""]) { problem = nil }
        } else if let youth = event.scout(id: scoutID) {
            SheetUnavailable(title: "\(youth.shownFullName) Has No Board Type",
                             text: "Choose Final Board or Proposal Review for them on the Youth page. Nothing was changed.")
        } else {
            SheetUnavailable(title: "That Youth Is No Longer on the List", text: "Nothing was changed.")
        }
    }

    /// − on a member. With the focus on it, the focus goes to the next
    /// member's − as listed, or to Find an adult once no one is left.
    private func remove(_ id: Adult.ID, from members: [Adult]) {
        let hadFocus = focus == .remove(id)
        let next = ListFocus.row(after: id, in: members.map(\.id))
        memberIDs.removeAll { $0 == id }
        if hadFocus {
            focus = next.map { .remove($0) } ?? .findAdult
        }
    }
}

/// Adults free to join this board, plus its own members not yet checked
/// again after being removed by hand. Click one to add them, or press Return
/// in Find an adult to add the first one found.
private struct FreeAdultsToAddSection: View {
    let youth: Scout
    let event: BoardEvent
    let boardType: BoardType
    @Binding var memberIDs: [String]
    @Binding var search: String
    let focus: FocusState<SchedulerFocus?>.Binding

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let candidates = event.adults
            .filter { ($0.canJoin(boardType) || $0.room == youth.room) && !memberIDs.contains($0.id) }
            .filter { query.isEmpty || $0.shownFullName.localizedCaseInsensitiveContains(query)
                || $0.unitName.localizedCaseInsensitiveContains(query) || $0.unitLabel.localizedCaseInsensitiveContains(query)
                || $0.unitDisplay.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let lhsChairs = lhs.canChair(boardType), rhsChairs = rhs.canChair(boardType)
                if lhsChairs != rhsChairs { return lhsChairs }
                return (lhs.last, lhs.first) < (rhs.last, rhs.first)
            }

        Section {
            TextField("Find an adult", text: $search, prompt: Text("Name or unit"))
                .labelsHidden()
                .focused(focus, equals: .findAdult)
                // Only once something is typed: Return in the empty field
                // would otherwise add whoever heads the list.
                .onSubmit { if !query.isEmpty, let first = candidates.first { add(first, from: candidates) } }
                // An adult whose + has the focus can leave the list with no
                // button pressed, put on another board or gone home: the
                // focus goes to the row in their place. On this one row, not
                // the section, which hands its modifiers to every row.
                .onChange(of: candidates.map(\.id)) { old, new in
                    if case .add(let id)? = focus.wrappedValue, !new.contains(id) {
                        focus.wrappedValue = ListFocus.row(id, in: old, becoming: new).map { .add($0) } ?? .findAdult
                    }
                }
            if candidates.isEmpty {
                Text(query.isEmpty ? "Everyone who could sit is on a board." : "No free adult matches.")
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { adult in
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text(adult.shownFullName)
                        AdultMarks(adult: adult, youth: youth)
                        Spacer()
                        Text(adult.unitDisplay).font(.caption).foregroundStyle(.secondary)
                        RoleText(role: adult.role(for: boardType)?.rawValue ?? "")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(adult.spokenRow(youth: youth, place: adult.unitDisplay,
                                                        role: adult.role(for: boardType)?.label ?? ""))
                    Button {
                        add(adult, from: candidates)
                    } label: {
                        Image(systemName: "plus.circle").memberButtonTarget()
                    }
                    .focused(focus, equals: .add(adult.id))
                    .buttonStyle(.borderless)
                    .help("Put \(adult.shownFullName) on this board")
                    .accessibilityLabel("Add \(adult.shownFullName)")
                }
                .contentShape(Rectangle())
                .onTapGesture { add(adult, from: candidates) }
            }
        } header: {
            Text("Free for a \(boardType.label) (\(candidates.count))").heading(.h2)
        }
    }

    /// With the focus on their +, the focus goes to the next adult's +, or
    /// to Find an adult once no one is left.
    private func add(_ adult: Adult, from candidates: [Adult]) {
        let hadFocus = focus.wrappedValue == .add(adult.id)
        let next = ListFocus.row(after: adult.id, in: candidates.map(\.id))
        memberIDs.append(adult.id)
        search = ""
        if hadFocus {
            focus.wrappedValue = next.map { .add($0) } ?? .findAdult
        }
    }
}
