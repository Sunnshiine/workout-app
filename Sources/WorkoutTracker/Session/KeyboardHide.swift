import CoreGraphics

enum KeyboardHide {
    // A hardware keyboard minimizes the software keyboard to a bar that posts a hide but stays on
    // screen, so only an end frame wholly below the screen counts as the keyboard leaving.
    static func leavesScreen(endFrame: CGRect, screenBounds: CGRect) -> Bool {
        endFrame.minY >= screenBounds.maxY
    }
}
