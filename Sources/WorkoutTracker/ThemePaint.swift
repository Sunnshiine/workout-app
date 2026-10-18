import SwiftUI

extension Theme {
    // MARK: - Paint box

    /// The small set of pigments every role is mixed from (token sheet §2). Most roles are
    /// `paint @ opacity`; wash recipes, glows and `tileCurrentBorder` are honest literals.
    enum Paint {
        static let ink = rgb(21, 33, 24)  // #152118 — day text
        static let inkNight = rgb(239, 243, 227)  // #EFF3E3 — night text
        static let muted = rgb(64, 78, 68)  // #404E44 — day secondary
        static let mutedNight = rgb(154, 170, 155)  // #9AAA9B — night secondary
        static let mutedNightLight = rgb(170, 186, 170)  // #AABAAA — night Superset partner name
        static let cream = rgb(242, 247, 232)  // #F2F7E8 — the workhorse
        static let actionDay = rgb(13, 107, 64)  // #0D6B40 — day action / leaf / stem / bird
        static let actionNight = rgb(31, 133, 82)  // #1F8552 — night action (mint is banned at night)
        static let actionDayInk = rgb(10, 89, 54)
        static let actionNightInk = rgb(168, 207, 180)
        static let foliage = rgb(87, 145, 104)  // #579168 — the night pigment
        static let foliageDeep = rgb(63, 106, 75)  // #3F6A4B — day Superset partner name
        static let paperDayTop = rgb(233, 238, 220)  // #E9EEDC
        static let paperDayBottom = rgb(203, 225, 194)  // #CBE1C2
        static let paperNightTop = rgb(35, 44, 32)  // #232C20
        static let paperNightBottom = rgb(18, 29, 20)  // #121D14
        // The Sunbird colophon's three-stop glass greens (token sheet §Bird & colophon). The glass
        // mark keeps its icon greens in both appearances — "unchanged at night".
        static let colophonGlassTop = rgb(74, 160, 108)  // #4AA06C
        static let colophonGlassMid = rgb(14, 110, 67)  // #0E6E43
        static let colophonGlassBottom = rgb(8, 78, 47)  // #084E2F
    }

    // MARK: - Paper wash

    /// One radial light wash in the living-paper recipe. Fractions and centre come straight from
    /// the token-sheet CSS; the SwiftUI render is an elliptical approximation revalidated by the
    /// visual gate (ADR-0007).
    struct RadialWash: Equatable {
        let color: Color
        let center: UnitPoint
        let radiusFraction: Double
    }

    /// The layered living-paper recipe for one appearance: a base sage pair under four radial
    /// washes (token sheet §3, `paperWash`). Replaces the retired two-stop `gradientStops`.
    struct PaperRecipe: Equatable {
        let baseTop: Color
        let baseBottom: Color
        /// Bottom-to-top paint order (base first when rendered).
        let washes: [RadialWash]
    }

    // MARK: - Elevation & light kit

    /// A single CSS box-shadow transcribed verbatim from the token sheet. Offsets, `blur` and
    /// `spread` keep the sheet's px values; `swiftUIRadius` maps CSS blur onto SwiftUI's radius
    /// (≈ blur / 2). `isInset` distinguishes the night "border-as-light" recipes (an inset stroke,
    /// not a drop) from the day drops. These are foundation roles: later composition slices consume
    /// them, so slice 1 verifies the values behind the seam even before a view reads them.
    struct BoxShadow: Equatable {
        let xOffset: CGFloat
        let yOffset: CGFloat
        let blur: CGFloat
        let spread: CGFloat
        let color: Color
        let isInset: Bool

        init(
            x xOffset: CGFloat = 0,
            y yOffset: CGFloat,
            blur: CGFloat,
            spread: CGFloat = 0,
            color: Color,
            inset isInset: Bool = false
        ) {
            self.xOffset = xOffset
            self.yOffset = yOffset
            self.blur = blur
            self.spread = spread
            self.color = color
            self.isInset = isInset
        }

        /// The nearest SwiftUI `.shadow(radius:)` for this CSS blur.
        var swiftUIRadius: CGFloat { blur / 2 }
    }

    /// A radial light recipe with explicit multi-stop colour ramp (the page sunbeam and a tile's
    /// top-light are multi-stop, unlike the single-colour `RadialWash`).
    struct RadialLight: Equatable {
        /// Gradient stops with `location` in 0…1.
        let stops: [Gradient.Stop]
        let center: UnitPoint
        let radiusFraction: Double
    }

    /// An Exercise-History data-point marker (token sheet §Exercise History). `lineWidth == 0`
    /// means a filled dot; a non-zero width is a hollow outline. `hasPaperCore` punches the paper
    /// through a solid dot so it reads as a plotted point, not a blob.
    struct DotSpec: Equatable {
        let radius: CGFloat
        let lineWidth: CGFloat
        let hasPaperCore: Bool
    }

    enum LightKit {
        /// The collapsed week card's quiet shade (`cardLow`) — it sits "in shade" under the focus card.
        static let cardLow: [BoxShadow] = [
            BoxShadow(y: 1, blur: 2, color: Paint.ink.opacity(0.06)),
            BoxShadow(y: 3, blur: 8, color: Paint.ink.opacity(0.07))
        ]

        /// The volume chart's plotted points: a solid ink dot with a paper core, and the
        /// approximate-value dot as a hollow ink outline.
        static let dataDot = DotSpec(radius: 4.5, lineWidth: 0, hasPaperCore: true)
        static let approxDot = DotSpec(radius: 4, lineWidth: 1.5, hasPaperCore: false)
    }
}

// MARK: - Radial light

extension Theme.RadialLight {
    /// The multi-stop radial recipe (the Block-grid page sunbeam, a tile's top-light) rendered
    /// as a fillable view — an elliptical gradient carrying the exact stops, centre and reach
    /// transcribed from the token sheet. Drop it into an `.overlay`/`.background` over the surface
    /// it lights.
    var gradientView: some View {
        EllipticalGradient(
            gradient: Gradient(stops: stops),
            center: center,
            startRadiusFraction: 0,
            endRadiusFraction: radiusFraction
        )
    }
}

// MARK: - Living-paper background

extension Theme.Palette {
    /// The living-paper wash rendered as the background of every non-system surface (token sheet
    /// §3). One recipe per appearance; the base sage pair sits under the four radial washes.
    var paperBackground: some View {
        ZStack {
            LinearGradient(
                colors: [paper.baseTop, paper.baseBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            ForEach(Array(paper.washes.enumerated()), id: \.offset) { _, wash in
                EllipticalGradient(
                    colors: [wash.color, .clear],
                    center: wash.center,
                    startRadiusFraction: 0,
                    endRadiusFraction: wash.radiusFraction
                )
            }
        }
    }
}

// MARK: - Elevation

extension View {
    /// Applies a token-sheet elevation recipe (`surfaceShadow`, `logShadow`, the light kit). Drop
    /// shadows stack as SwiftUI shadows; an inset recipe — the Night "border-as-light" — renders as
    /// an inset stroke on `shape` instead of a drop (token sheet §Active Set Card / §Log capsule).
    func themeElevation(_ shadows: [Theme.BoxShadow], in shape: some InsettableShape) -> some View {
        modifier(Theme.Elevation(shadows: shadows, shape: shape))
    }

    func themeCarve(_ palette: Theme.Palette, in shape: some InsettableShape) -> some View {
        background {
            shape
                .fill(palette.chipCarvedFill.shadow(.inner(color: palette.chipCarveShadow, radius: 1, y: 1)))
                .overlay {
                    // The light bottom lip — the stroke masked to the lower edge so only the bottom lights.
                    shape
                        .strokeBorder(palette.chipCarveEdge, lineWidth: 1)
                        .mask {
                            LinearGradient(
                                colors: [.clear, .clear, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
        }
    }
}

extension Theme {
    struct Elevation<Bed: InsettableShape>: ViewModifier {
        let shadows: [BoxShadow]
        let shape: Bed

        func body(content: Content) -> some View {
            let drops = shadows.filter { !$0.isInset }
            let insets = shadows.filter(\.isInset)
            return drops.reduce(AnyView(content)) { view, shadow in
                AnyView(
                    view.shadow(
                        color: shadow.color,
                        radius: shadow.swiftUIRadius,
                        x: shadow.xOffset,
                        y: shadow.yOffset
                    )
                )
            }
            .overlay {
                ForEach(Array(insets.enumerated()), id: \.offset) { _, shadow in
                    shape.strokeBorder(shadow.color, lineWidth: max(shadow.spread, 1))
                }
            }
        }
    }
}
