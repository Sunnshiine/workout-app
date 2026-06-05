import SwiftUI

enum GlassSurface {
    case card
    case tile
    case lens
    case capsule
}

enum GlassProminence {
    case regular
    case clear

    var glass: Glass {
        switch self {
        case .regular:
            .regular
        case .clear:
            .clear
        }
    }
}

extension View {
    @ViewBuilder
    func workoutGlass(
        _ surface: GlassSurface,
        prominence: GlassProminence = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        let baseGlass = prominence.glass
        let tintedGlass = tint.map { baseGlass.tint($0) } ?? baseGlass
        let glass = interactive ? tintedGlass.interactive() : tintedGlass

        switch surface {
        case .card:
            glassEffect(glass, in: .rect(cornerRadius: Theme.cardCornerRadius))
        case .tile:
            glassEffect(glass, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))
        case .lens:
            glassEffect(glass, in: .rect(cornerRadius: Theme.lensCornerRadius))
        case .capsule:
            glassEffect(glass, in: .capsule)
        }
    }

    func workoutGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        glassEffectID(id, in: namespace)
    }

    func workoutGlassUnion(id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        glassEffectUnion(id: id, namespace: namespace)
    }

    func workoutGlassTransition(_ transition: GlassEffectTransition) -> some View {
        glassEffectTransition(transition)
    }
}

extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    static var workoutGlass: Self { .glass }
}

extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    static var workoutGlassProminent: Self { .glassProminent }
}

struct WorkoutGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = Theme.cardSpacing, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}
