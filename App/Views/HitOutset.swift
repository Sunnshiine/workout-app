import SwiftUI

extension View {
    /// Grows a short control's tap frame by `outset` above and below. Put it inside the Button's
    /// label, so the frame VoiceOver reports grows too, and `givingBackHitOutset` outside, so the
    /// layout doesn't move (DESIGN.md §8).
    func hitOutset(_ outset: CGFloat) -> some View {
        padding(.vertical, outset).contentShape(Rectangle())
    }

    func givingBackHitOutset(_ outset: CGFloat) -> some View {
        padding(.vertical, -outset)
    }
}

enum HitOutset {
    /// Takes a one-line control 17 to 19pt tall past 44pt.
    static let textLine: CGFloat = 14
}
