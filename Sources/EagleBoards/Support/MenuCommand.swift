import SwiftUI

/// One command that both a menu bar menu and a context menu list. The menu
/// bar shows every item, dimmed while it does not apply, with its key, so
/// the menu keeps its shape and teaches the shortcut. A context menu shows
/// only what applies to what was clicked, and no keys (HIG, Context menus).
struct MenuCommand: View {
    let title: String
    let applies: Bool
    let shortcut: KeyboardShortcut?
    let inContextMenu: Bool
    let action: @MainActor () -> Void

    init(
        _ title: String, applies: Bool, shortcut: KeyboardShortcut? = nil, inContextMenu: Bool,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.applies = applies
        self.shortcut = shortcut
        self.inContextMenu = inContextMenu
        self.action = action
    }

    var body: some View {
        if applies || !inContextMenu {
            Button(title, action: action)
                .keyboardShortcut(inContextMenu ? nil : shortcut)
                .disabled(!applies)
        }
    }
}

/// A submenu in the menu bar, or, while it has nothing to offer, a dimmed
/// plain item with the same title. A disabled `Menu` or `Picker` there keeps
/// its title lit, with its chevron, and dims only what is inside, so the menu
/// would look as though it still applies.
struct SubmenuCommand<Submenu: View>: View {
    let title: String
    let applies: Bool
    let submenu: Submenu

    init(_ title: String, applies: Bool, @ViewBuilder submenu: () -> Submenu) {
        self.title = title
        self.applies = applies
        self.submenu = submenu()
    }

    var body: some View {
        if applies {
            submenu
        } else {
            Button(title) {}
                .disabled(true)
        }
    }
}
