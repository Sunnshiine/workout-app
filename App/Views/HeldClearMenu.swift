import SwiftUI
import UIKit

/// The held Set's Clear menu, told when it opens and when it closes, however it closes. A SwiftUI
/// menu's content can outlive its menu: closed by XCUITest, it never disappeared.
struct HeldClearMenu: UIViewRepresentable {
    let tint: Color
    let onOpened: () -> Void
    let onClosed: () -> Void
    let onClear: () -> Void

    func makeUIView(context: Context) -> MenuReportingButton {
        let button = MenuReportingButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        // The body style at large scale, as SwiftUI sizes `.imageScale(.large)`, so it grows with Dynamic Type.
        button.setImage(
            UIImage(
                systemName: "ellipsis",
                withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .large)
            ),
            for: .normal
        )
        button.accessibilityLabel = "More"
        button.accessibilityIdentifier = "clear-logged-set-menu"
        return button
    }

    func updateUIView(_ button: MenuReportingButton, context: Context) {
        button.tintColor = UIColor(tint)
        button.onOpened = onOpened
        button.onClosed = onClosed
        button.menu = UIMenu(children: [
            UIAction(title: "Clear", attributes: .destructive) { [onClear] _ in onClear() }
        ])
    }
}

final class MenuReportingButton: UIButton {
    var onOpened: () -> Void = {}
    var onClosed: () -> Void = {}

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        onOpened()
    }

    /// UIKit runs a chosen action before the menu ends, so a Clear lands before the close.
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        onClosed()
    }
}
