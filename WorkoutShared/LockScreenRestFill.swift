import SwiftUI

struct LockScreenLeaf {
    let card: Color
    let fill: Color
    /// The fill one step toward the action green, which it flashes as a rest begins.
    let flash: Color

    static func colors(for appearance: LiveActivityAppearance) -> LockScreenLeaf {
        switch appearance {
        case .dark:
            LockScreenLeaf(
                card: Color(oklchLightness: 0.2, chroma: 0.03, hue: 156),
                fill: Color(oklchLightness: 0.29, chroma: 0.055, hue: 156),
                flash: Color(oklchLightness: 0.43, chroma: 0.095, hue: 156)
            )
        case .light:
            LockScreenLeaf(
                card: Color(oklchLightness: 0.95, chroma: 0.025, hue: 156),
                fill: Color(oklchLightness: 0.88, chroma: 0.06, hue: 156),
                flash: Color(oklchLightness: 0.78, chroma: 0.11, hue: 156)
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

    /// Nil with no rest and a Set still to log, which leaves the card its plain green.
    var lockScreenFill: LockScreenFill? {
        if let interval = wholeRestInterval { return .draining(over: interval) }
        return loggablePress == .settled ? .whole : nil
    }
}

/// The lighter green the card's background fills with.
enum LockScreenFill: Hashable {
    /// Drains from the right as the rest runs out.
    case draining(over: ClosedRange<Date>)
    /// Stays whole: the Set is logged and no rest follows it.
    case whole

    /// What the fill's layers are keyed on. A Live Activity keeps a `String` identity from one
    /// update to the next, but inserts a view keyed on the dates afresh at every update, which
    /// flashed the fill at every turn of the card.
    var identity: String {
        switch self {
        case .draining(let interval): "\(interval.lowerBound.timeIntervalSinceReferenceDate)"
        case .whole: "whole"
        }
    }
}

/// The card's green is drawn here as well as in the background tint, because the system draws the
/// tint darker than it draws the fill.
///
/// A fill that takes another's place says a Set was logged: it runs back to full in the flash
/// green, and the plain fill fades in over it. Both layers are keyed on the fill, so one update
/// draws all of it and the card needs no logged state to clear.
struct LockScreenCardBackground: View {
    let leaf: LockScreenLeaf
    let fill: LockScreenFill?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        leaf.card
            .overlay {
                if let fill {
                    ZStack {
                        ZStack {
                            layer(leaf.flash, fill)
                                .id(fill.identity)
                                .transition(.asymmetric(insertion: reduceMotion ? .opacity : .move(edge: .leading), removal: .opacity))
                        }
                        .animation(LockScreenCardMotion.refill, value: fill.identity)

                        ZStack {
                            layer(leaf.fill, fill)
                                .id(fill.identity)
                                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                        }
                        .animation(LockScreenCardMotion.flashFade, value: fill.identity)
                    }
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layer(_ color: Color, _ fill: LockScreenFill) -> some View {
        switch fill {
        case .draining(let interval):
            // The bar's track lets about a quarter of the fill through, and each pass cuts that
            // again, so three leave the drained side at the card's green.
            color
                .mask { SystemClockDrain(interval: interval) }
                .mask { SystemClockDrain(interval: interval) }
                .mask { SystemClockDrain(interval: interval) }
        case .whole:
            color
        }
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
