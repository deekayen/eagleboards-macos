import EagleBoardsCore
import SwiftUI

/// The operator's screen for the evening: youth waiting, adults available,
/// the rooms, and every board so far.
///
/// Nothing here polls. The event night is observed directly, so a youth who
/// signs in at the door appears the moment the tablet's request lands.
struct SchedulerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let night: EventNight

    var body: some View {
        @Bindable var model = model

        VSplitView {
            HSplitView {
                YouthPanel(night: night)
                    .frame(minWidth: 540, idealWidth: 700)
                AdultPanel(night: night)
                    .frame(minWidth: 420, idealWidth: 560)
            }
            .frame(minHeight: 280, idealHeight: 420)

            RoomsPanel(night: night)
                .frame(minHeight: 150, idealHeight: 210)

            BoardsPanel(night: night)
                .frame(minHeight: 120, idealHeight: 200)
        }
        .navigationTitle("Eagle Boards")
        .navigationSubtitle(nightSubtitle)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) { NoticeBanner() }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .seatBoard(let scoutID): SeatBoardSheet(night: night, scoutID: scoutID)
            case .completeBoard(let scoutID): CompleteBoardSheet(night: night, scoutID: scoutID)
            case .addRoom: AddRoomSheet(night: night)
            case .swapRooms(let roomID): SwapRoomsSheet(night: night, firstRoomID: roomID)
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
        .alert(
            "Not done",
            isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.problem ?? "")
        }
    }

    private var nightSubtitle: String {
        night.night == model.today ? "Tonight, \(night.night)" : "\(night.night) (an earlier night)"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            CheckInStatusButton()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await model.importSignUps() }
            } label: {
                Label("Import Sign-Ups", systemImage: "square.and.arrow.down")
            }
            .help("Import tonight's pre-registrations and adult sign-ups from SignUpGenius")
            .disabled(model.isImporting)

            Button {
                openWindow(id: WindowID.records)
            } label: {
                Label("Records", systemImage: "tablecells")
            }
            .help("View and edit every record: youth, adults, the adult history and rooms")
        }
    }
}

/// A short-lived message along the bottom of the window.
struct NoticeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let notice = model.notice {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol(for: notice.kind))
                    .foregroundStyle(color(for: notice.kind))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.title).font(.headline)
                    ForEach(Array(notice.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    model.notice = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(12)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color(for: notice.kind).opacity(0.5)))
            .shadow(radius: 6, y: 2)
            .padding(16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: notice.id) {
                // Problems and located adults stay up longer: they are read, not glanced at.
                let seconds: Double = notice.kind == .success ? 5 : 20
                try? await Task.sleep(for: .seconds(seconds))
                if model.notice?.id == notice.id {
                    withAnimation { model.notice = nil }
                }
            }
        }
    }

    private func symbol(for kind: AppModel.Notice.Kind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .info: "person.crop.circle.badge.questionmark"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: AppModel.Notice.Kind) -> Color {
        switch kind {
        case .success: .green
        case .info: .blue
        case .problem: .orange
        }
    }
}

/// A panel's title bar with its buttons, like the Java scheduler's toolbars.
struct PanelHeader<Actions: View>: View {
    let title: String
    var detail: String = ""
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            if !detail.isEmpty {
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) { actions }
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// A short vertical rule between groups of buttons. A bare Divider in an
/// HStack stretches to the full height available, which inflates the header.
struct ToolbarSeparator: View {
    var body: some View {
        Divider().frame(height: 16).padding(.horizontal, 2)
    }
}
