import AppKit
import SwiftUI

/// Binds a toolbar search's focus where the system can (macOS 15 and later).
struct SearchFocus: ViewModifier {
    let isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.searchFocused(isFocused)
        } else {
            content
        }
    }
}

/// Edit › Find…: put the cursor in the front window's toolbar search, the
/// one `isFocused` is bound to with `SearchFocus`.
@MainActor
func startToolbarSearch(_ isFocused: FocusState<Bool>.Binding) {
    if #available(macOS 15, *) {
        isFocused.wrappedValue = true
    } else {
        // macOS 14 has no searchFocused; the toolbar's search item starts
        // its own interaction instead. Front to back, so it is the search of
        // the window Find is about.
        NSApplication.shared.orderedWindows
            .lazy
            .compactMap { $0.toolbar?.items.lazy.compactMap { $0 as? NSSearchToolbarItem }.first }
            .first?
            .beginSearchInteraction()
    }
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
