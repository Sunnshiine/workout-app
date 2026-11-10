import SwiftUI

struct LockScreenLeaf {
    let card: Color
    let fill: Color

    static func colors(for appearance: LiveActivityAppearance) -> LockScreenLeaf {
        switch appearance {
        case .dark:
            LockScreenLeaf(
                card: Color(oklchLightness: 0.2, chroma: 0.03, hue: 156),
                fill: Color(oklchLightness: 0.29, chroma: 0.055, hue: 156)
            )
        case .light:
            LockScreenLeaf(
                card: Color(oklchLightness: 0.95, chroma: 0.025, hue: 156),
                fill: Color(oklchLightness: 0.88, chroma: 0.06, hue: 156)
            )
        }
    }
}

extension WorkoutActivityAttributes.ContentState {
    var lockScreenLeaf: LockScreenLeaf {
        .colors(for: appearance)
    }

    var wholeRestInterval: ClosedRange<Date>? {
        guard let restStartDate, let restEndDate, restEndDate > restStartDate else { return nil }
        return restStartDate...restEndDate
    }
}

/// The card's green is drawn here as well as in the background tint, because the system draws the
/// tint darker than it draws the fill.
struct LockScreenCardBackground: View {
    let leaf: LockScreenLeaf
    let restFill: ClosedRange<Date>?

    var body: some View {
        leaf.card
            .overlay {
                if let interval = restFill {
                    // The bar's track lets about a quarter of the fill through, and each pass cuts
                    // that again, so three leave the drained side at the card's green.
                    leaf.fill
                        .mask { SystemClockDrain(interval: interval) }
                        .mask { SystemClockDrain(interval: interval) }
                        .mask { SystemClockDrain(interval: interval) }
                }
            }
            .accessibilityHidden(true)
    }
}

/// A full-height bar the system clock drains with no update from the app. A Live Activity redraws
/// only a timer `Text` and a timer `ProgressView` on its own, a custom `ProgressViewStyle` gets no
/// fraction from the timer, and `scaleEffect` is the one thing that makes the linear bar taller.
private struct SystemClockDrain: View {
    /// Tall enough that the bar's rounded end is a straight edge over the height of any card.
    private static let stretch: CGFloat = 400

    let interval: ClosedRange<Date>

    var body: some View {
        ProgressView(timerInterval: interval, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .labelsHidden()
        .tint(.white)
        .scaleEffect(x: 1, y: Self.stretch)
    }
}
