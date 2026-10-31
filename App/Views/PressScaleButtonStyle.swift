import SwiftUI

/// The press every primary capsule shares with the Log capsule (DESIGN.md §7): it sinks to
/// `Theme.pressScale` on touch-down and springs back when the finger lifts or leaves.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Theme.pressScale : 1)
            .animation(Theme.pressAnimation, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressScaleButtonStyle {
    static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }
}
