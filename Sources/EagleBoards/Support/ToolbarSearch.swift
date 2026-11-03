import SwiftUI

/// Binds a toolbar search's focus to `isFocused`, so Edit › Find… can move the
/// cursor into it.
struct SearchFocus: ViewModifier {
    let isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content.searchFocused(isFocused)
    }
}

/// Edit › Find…: put the cursor in the front window's toolbar search, the
/// one `isFocused` is bound to with `SearchFocus`.
@MainActor
func startToolbarSearch(_ isFocused: FocusState<Bool>.Binding) {
    isFocused.wrappedValue = true
}

/// Edit › Find… while the Help window is in front: its own search, not the
/// scheduler's.
struct HelpSearchAction {
    let start: @MainActor () -> Void
}

private struct HelpSearchKey: FocusedValueKey {
    typealias Value = HelpSearchAction
}

extension FocusedValues {
    var helpSearch: HelpSearchAction? {
        get { self[HelpSearchKey.self] }
        set { self[HelpSearchKey.self] = newValue }
    }
}
