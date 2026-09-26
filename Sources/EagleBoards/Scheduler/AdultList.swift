import EagleBoardsCore
import SwiftUI

/// Every adult who has signed in tonight. Select several with Command or
/// Shift and add them to the board being drawn up, or drag them onto it in
/// the inspector.
struct AdultList: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var sortOrder = [KeyPathComparator(\Adult.last)]

    var body: some View {
        @Bindable var model = model
        let draft = model.draft
        let rows = night.adults
            .filter { matches(model.searchText, $0) }
            .sorted(using: sortOrder)

        Table(of: Adult.self, selection: $model.selectedAdultIDs, sortOrder: $sortOrder) {
            TableColumn("Status", value: \.room) { adult in
                AdultStatusLabel(adult: adult, isOnDraft: draft?.memberIDs.contains(adult.id) == true)
            }
            .width(min: 80, ideal: 110, max: 150)
            TableColumn("Last", value: \.last)
            TableColumn("First", value: \.first)
            TableColumn("Unit", value: \.unitName) { adult in
                Text(adult.unitLabel).help(adult.unitName)
            }
            .width(min: 44, ideal: 60, max: 90)
            TableColumn("Final", value: \.finalBoardRoleText) { adult in
                RoleText(role: adult.finalBoardRoleText)
            }
            .width(min: 50, ideal: 70, max: 90)
            TableColumn("Project", value: \.projectReviewRoleText) { adult in
                RoleText(role: adult.projectReviewRoleText)
            }
            .width(min: 50, ideal: 70, max: 90)
            // Volunteering toward a Wood Badge ticket item.
            TableColumn("WB", value: \.woodBadge) { adult in
                if adult.woodBadge == "Y" {
                    WoodBadgeIcon()
                }
            }
            .width(min: 28, ideal: 34, max: 44)
            TableColumn("With", value: \.supporting) { adult in
                let names = supportedNames(adult)
                Text(names).foregroundStyle(.secondary).help(names)
            }
        } rows: {
            ForEach(rows) { adult in
                TableRow(adult).draggable(DragPayload.adult(adult.id))
            }
        }
        .contextMenu(forSelectionType: Adult.ID.self) { ids in
            AdultActionButtons(model: model, adultIDs: ids)
        } primaryAction: { ids in
            model.addToDraft(Array(ids))
        }
        .overlay {
            if rows.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView("No Adults Yet", systemImage: "person.2",
                                           description: Text("Adults appear here the moment they sign in at the tablet."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
    }

    private func supportedNames(_ adult: Adult) -> String {
        adult.supporting.split(separator: "|")
            .compactMap { night.scout(id: String($0))?.fullName }
            .joined(separator: ", ")
    }

    private func matches(_ search: String, _ adult: Adult) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [adult.fullName, adult.unitName, adult.unitLabel, adult.room, adult.email]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Free, on a board in a room, or gone home -- in words and a symbol, not
/// only a color.
struct AdultStatusLabel: View {
    let adult: Adult
    var isOnDraft = false

    var body: some View {
        if adult.isDisabledForTonight {
            Label("Gone home", systemImage: "moon.zzz")
                .foregroundStyle(.secondary)
                .help("Disabled for today. Enable brings them back.")
        } else if adult.isOnBoard {
            Label("Room \(adult.room)", systemImage: "person.3.fill")
                .help("On the board in room \(adult.room)")
        } else if isOnDraft {
            Label("This board", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .help("On the board being drawn up for the selected youth")
        } else {
            Label("Free", systemImage: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

/// What can be done to adults: the Adult menu, and the context menu on their
/// rows. Acting on rows that are not selected selects them first.
struct AdultActionButtons: View {
    let model: AppModel
    /// Nil acts on the selected adults.
    var adultIDs: Set<Adult.ID>?

    var body: some View {
        let youth = model.selectedYouth
        let draft = model.draft
        let ids = adultIDs ?? model.selectedAdultIDs
        let adults = model.night?.adults.filter { ids.contains($0.id) } ?? []
        let single = adults.count == 1 ? adults.first : nil

        Button(youth.map { "Add to \($0.first)'s Board" } ?? "Add to Board") {
            run { model.addToDraft(Array(ids)) }
        }
        .keyboardShortcut("b")
        .disabled(draft == nil || !ids.contains { draft?.memberIDs.contains($0) == false })
        Button("Remove from Board") { run { model.removeFromDraft(ids) } }
            .disabled(draft == nil || !ids.contains { draft?.memberIDs.contains($0) == true })
        Divider()
        if let single, let youth, single.supports(youth.id) {
            Button("Unlink from \(youth.fullName)") { run { model.toggleSupportLink() } }
        } else {
            Button(youth.map { "Came to Support \($0.fullName)" } ?? "Came to Support the Selected Youth") {
                run { model.toggleSupportLink() }
            }
            .disabled(single == nil || youth == nil)
        }
        Divider()
        Button("Enable for Today") { run { model.setAvailable(true) } }
            .disabled(!adults.contains(where: \.isDisabledForTonight))
        Button("Disable for Today") { run { model.setAvailable(false) } }
            .disabled(!adults.contains(where: \.isAvailable))
    }

    private func run(_ action: () -> Void) {
        if let adultIDs, !adultIDs.isEmpty, !adultIDs.isSubset(of: model.selectedAdultIDs) {
            model.selectedAdultIDs = adultIDs
        }
        action()
    }
}

/// A board role, with Chair made easy to spot.
struct RoleText: View {
    let role: String

    var body: some View {
        switch BoardRole(rawValue: role) {
        case .chair:
            Text("Chair").fontWeight(.semibold).foregroundStyle(.tint)
        case .unavailable:
            Text("—").foregroundStyle(.secondary).help("No thanks")
        default:
            Text(role)
        }
    }
}
