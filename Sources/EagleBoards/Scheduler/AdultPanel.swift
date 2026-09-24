import EagleBoardsCore
import SwiftUI

/// Adults who have signed in. Checking someone puts them on the next board;
/// checked adults float to the top.
struct AdultPanel: View {
    @Environment(AppModel.self) private var model
    let night: EventNight
    @State private var sortOrder = [KeyPathComparator(\Adult.last)]

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            PanelHeader(title: "Adult Board Members", detail: checkedSummary) {
                Toggle("Show Busy", isOn: $model.showBusyAdults)
                    .toggleStyle(.button)
                    .help("Also show adults already on a board, disabled for tonight, or unavailable for this kind of board")
                Button("Clear") { model.checkedAdultIDs = [] }
                    .disabled(model.checkedAdultIDs.isEmpty)
                    .help("Uncheck everyone")
                ToolbarSeparator()
                Button("Enable") { model.confirmAvailability(true) }
                    .disabled(selectedAdult?.isDisabledForTonight != true)
                    .help("Bring a disabled adult back into the pool")
                Button("Disable") { model.confirmAvailability(false) }
                    .disabled(selectedAdult?.isAvailable != true)
                    .help("Take an adult out of the pool for tonight, for example because they have gone home")
            }
            Table(rows, selection: $model.selectedAdultID, sortOrder: $sortOrder) {
                TableColumn("") { adult in
                    checkbox(for: adult)
                }
                .width(22)
                TableColumn("Last", value: \.last) { adult in
                    styled(Text(adult.last), adult)
                }
                TableColumn("First", value: \.first) { adult in
                    styled(Text(adult.first), adult)
                }
                TableColumn("Unit", value: \.unitName) { adult in
                    styled(Text(adult.unitLabel), adult).help(adult.unitName)
                }
                .width(min: 44, ideal: 60, max: 90)
                TableColumn("Room", value: \.room) { adult in
                    styled(Text(adult.isDisabledForTonight ? "Off" : adult.room), adult)
                        .help(adult.isDisabledForTonight ? "Disabled for tonight" : "")
                }
                .width(min: 36, ideal: 44, max: 70)
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
                    Text(adult.woodBadge == "Y" ? "\u{2713}" : "")
                        .help(adult.woodBadge == "Y" ? "Volunteering toward a Wood Badge ticket item" : "")
                }
                .width(min: 28, ideal: 34, max: 44)
            }
        }
    }

    private var selectedAdult: Adult? { model.selectedAdultID.flatMap { night.adult(id: $0) } }

    private var checkedSummary: String {
        let available = night.adults.filter(\.isAvailable).count
        let checked = model.checkedAdultIDs.count
        return checked > 0 ? "\(checked) checked · \(available) free" : "\(available) free"
    }

    /// Checked first, in the order they were checked, then everyone else in
    /// the chosen sort. By default only adults who could sit on the selected
    /// youth's board are listed.
    private var rows: [Adult] {
        let boardType = model.selectedYouth?.boardType
        let checked = model.checkedAdults
        let others = night.adults
            .filter { !model.checkedAdultIDs.contains($0.id) }
            .filter { adult in
                guard !model.showBusyAdults else { return true }
                guard adult.isAvailable else { return false }
                if let boardType {
                    return adult.role(for: boardType) != .unavailable
                }
                return adult.role(for: .finalBoard) != .unavailable || adult.role(for: .projectReview) != .unavailable
            }
            .sorted(using: sortOrder)
        return checked + others
    }

    private func checkbox(for adult: Adult) -> some View {
        let isChecked = model.checkedAdultIDs.contains(adult.id)
        let reason = adult.isDisabledForTonight
            ? "Disabled for tonight -- enable them first"
            : adult.isOnBoard ? "Already on the board in room \(adult.room)" : ""
        return Toggle("", isOn: Binding(get: { isChecked }, set: { model.setChecked($0, adultID: adult.id) }))
            .toggleStyle(.checkbox)
            .labelsHidden()
            // Someone on a board or gone home cannot join another one. Leave
            // the box usable only to uncheck them.
            .disabled(!adult.isAvailable && !isChecked)
            .help(reason.isEmpty ? "Put \(adult.fullName) on the next board" : reason)
    }

    private func styled(_ text: Text, _ adult: Adult) -> some View {
        let inSelectedRoom = !adult.room.isEmpty && adult.room == model.selectedRoom?.name
        return text
            .fontWeight(inSelectedRoom ? .bold : .regular)
            .foregroundStyle(adult.isDisabledForTonight ? Color.secondary : adult.isOnBoard ? Color.red : Color.primary)
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
            Text("—").foregroundStyle(.secondary).help("Unavailable")
        default:
            Text(role)
        }
    }
}
