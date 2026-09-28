import EagleBoardsCore
import SwiftUI

/// Text edited in place in a table row, on the pages that list the event's
/// records (SPEC.md P-6). It is saved on Return, when the field loses focus,
/// or when the page is left with it still open, so the next page never shows
/// an older value; Escape puts the value back. `save` returns false when the
/// change was refused, and the field shows what is on file again.
struct EditableText: View {
    let value: String
    let name: String
    let save: (String) -> Bool

    @State private var text: String
    @FocusState private var isFocused: Bool

    /// - Parameter name: what the field holds, for VoiceOver.
    init(_ value: String, name: String, save: @escaping (String) -> Bool) {
        self.value = value
        self.name = name
        self.save = save
        _text = State(initialValue: value)
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .accessibilityLabel(name)
            .help(value)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused { text = newValue }
            }
            .onExitCommand {
                text = value
                isFocused = false
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard typed != value else {
            text = value
            return
        }
        if !save(typed) { text = value }
    }
}

/// A value chosen from a menu in a table row. The row shows `label`; the menu
/// lists the choices with a check on the current one.
struct EditableChoice<Label: View>: View {
    let value: String
    let choices: [(value: String, label: String)]
    let name: String
    let save: (String) -> Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(choices, id: \.value) { choice in
                Toggle(choice.label, isOn: Binding(
                    get: { choice.value == value },
                    set: { _ in if choice.value != value { _ = save(choice.value) } }
                ))
            }
        } label: {
            // The chevron says the value is a menu, not just text.
            HStack(spacing: 3) {
                label()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(name)
        .help("Choose the \(name.lowercased())")
    }
}

extension EditableChoice where Label == Text {
    /// The choice's own label, or the stored value if it is not one of them.
    init(_ value: String, choices: [(value: String, label: String)], name: String, save: @escaping (String) -> Bool) {
        self.init(value: value, choices: choices, name: name, save: save) {
            Text(choices.first { $0.value == value }?.label ?? value)
        }
    }
}

/// The choices the record pages offer, labelled as the rest of the app says them.
enum RecordChoices {
    static let youthUnitTypes = UnitType.youthChoices.map { ($0.rawValue, $0.rawValue) }
    static let adultUnitTypes = UnitType.allCases.map { ($0.rawValue, $0.rawValue) }
    static let boardTypes = BoardType.allCases.map { ($0.rawValue, $0.label) }
    static let results = [("", "None")] + BoardResult.allCases.map { ($0.rawValue, $0.label) }
    static let roles = BoardRole.allCases.map { role in
        (role.rawValue, role == .unavailable ? "No Thanks" : role.rawValue)
    }
}
