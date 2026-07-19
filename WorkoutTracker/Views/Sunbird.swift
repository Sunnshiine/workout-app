import SwiftUI

/// The Sunbird's two visual marks (DESIGN.md §6).
///
/// - ``SunbirdColophon`` is the complete glass mark — the sun disc with the
///   negative-space bird cutout, and the **one surviving glass element** in the
///   app now that Liquid Glass is retired (ADR-0014). It keeps its icon greens
///   in both appearances and never renders below the 28pt honesty floor.
/// - ``PerchedSongbird`` is a separate drawing in the leaf language (not the
///   mark's glyph) with exactly two homes: centered on the Sheet-connect screen
///   and on the Move On ceremony's branch tip. It re-lights like a leaf at night
///   — foliage ink with a cream wing-hint and no glow.

// MARK: - The perched songbird

/// A small songbird drawn in the same leaf language as the stage branch. It fills
/// in `palette.birdFill` (day action / foliage at night) with a cream wing-hint
/// (`palette.birdRib`) and carries no glow — the bird is brand, not badge.
struct PerchedSongbird: View {
    /// The bird's rendered height in points; the silhouette keeps its aspect ratio.
    var height: CGFloat = 96
    @Environment(\.themePalette) private var palette

    // Design space of the silhouette (points), facing left and perched.
    private let designSize = CGSize(width: 128, height: 100)

    private var scale: CGFloat { height / designSize.height }

    var body: some View {
        ZStack {
            SongbirdShape()
                .fill(palette.birdFill)

            SongbirdWing()
                .stroke(palette.birdRib, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            // A single quiet eye in the paper's negative space keeps the mark
            // legible without adding a second ink; no glow, day or night.
            Circle()
                .fill(palette.paper.baseBottom)
                .frame(width: 6, height: 6)
                .position(x: 33, y: 34)
        }
        .frame(width: designSize.width, height: designSize.height)
        .scaleEffect(scale)
        .frame(width: designSize.width * scale, height: designSize.height * scale)
        .accessibilityHidden(true)
    }
}

/// The songbird silhouette — head, beak, plump leaf-language body, and a raised
/// tail — in a 128×100 design space, facing left and perched. Feet stubs anchor
/// the perched read even when the bird stands centered on the connect screen.
struct SongbirdShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Body + head + tail as one continuous silhouette (design space 128×100).
        path.move(to: CGPoint(x: 30, y: 30))  // crown
        path.addCurve(
            to: CGPoint(x: 14, y: 40),
            control1: CGPoint(x: 22, y: 28),
            control2: CGPoint(x: 16, y: 33)
        )
        path.addLine(to: CGPoint(x: 4, y: 42))  // beak tip
        path.addLine(to: CGPoint(x: 16, y: 47))  // beak underside
        path.addCurve(
            to: CGPoint(x: 34, y: 68),
            control1: CGPoint(x: 22, y: 54),
            control2: CGPoint(x: 26, y: 63)
        )
        path.addCurve(
            to: CGPoint(x: 74, y: 74),
            control1: CGPoint(x: 46, y: 76),
            control2: CGPoint(x: 62, y: 78)
        )
        path.addCurve(
            to: CGPoint(x: 124, y: 22),
            control1: CGPoint(x: 96, y: 70),
            control2: CGPoint(x: 112, y: 50)
        )  // sweep up the tail
        path.addCurve(
            to: CGPoint(x: 78, y: 40),
            control1: CGPoint(x: 108, y: 34),
            control2: CGPoint(x: 92, y: 40)
        )  // tail underside back to the back
        path.addCurve(
            to: CGPoint(x: 30, y: 30),
            control1: CGPoint(x: 58, y: 18),
            control2: CGPoint(x: 44, y: 20)
        )  // back over the crown
        path.closeSubpath()

        // Two short feet stubs to the perch line.
        path.move(to: CGPoint(x: 44, y: 72))
        path.addLine(to: CGPoint(x: 44, y: 84))
        path.move(to: CGPoint(x: 58, y: 74))
        path.addLine(to: CGPoint(x: 58, y: 86))

        return path.applying(scaleTransform(into: rect))
    }

    private func scaleTransform(into rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(scaleX: rect.width / 128, y: rect.height / 100)
    }
}

/// The cream wing-hint — a single leaf-rib curve laid over the body.
struct SongbirdWing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 40, y: 44))
        path.addCurve(
            to: CGPoint(x: 88, y: 54),
            control1: CGPoint(x: 58, y: 40),
            control2: CGPoint(x: 74, y: 46)
        )
        return path.applying(CGAffineTransform(scaleX: rect.width / 128, y: rect.height / 100))
    }
}

// MARK: - The Sunbird colophon (the one glass disc)

/// The complete Sunbird mark: the sun disc with a negative-space bird cutout,
/// rendered as the app's single surviving glass element. It keeps its icon greens
/// in both appearances (never re-lit) and refuses to render below the 28pt floor.
struct SunbirdColophon: View {
    /// The rendered diameter; clamped to the 28pt honesty floor (DESIGN.md §6).
    var diameter: CGFloat = 40

    // The icon greens, held fixed across appearances (The Mark Stays Whole).
    private static let sunTop = Color(red: 0.30, green: 0.62, blue: 0.36)
    private static let sunBottom = Color(red: 13.0 / 255.0, green: 107.0 / 255.0, blue: 64.0 / 255.0)

    private var renderedDiameter: CGFloat { max(28, diameter) }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Self.sunTop, Self.sunBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                // The bird lives as negative space — a cutout, never a positive
                // bird laid on top (The Mark Stays Whole).
                SongbirdShape()
                    .fill(Color.black)
                    .blendMode(.destinationOut)
                    .padding(renderedDiameter * 0.2)
            }
            .compositingGroup()
            .frame(width: renderedDiameter, height: renderedDiameter)
            .glassEffect(.regular, in: .circle)
            .accessibilityHidden(true)
    }
}
