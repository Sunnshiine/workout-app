import SwiftUI

/// The Sunbird colophon — the app icon's whole glass mark (#370, DESIGN.md §6),
/// used quietly in-app as a brand element. It is the app's *one* glass survivor
/// (ADR-0014): a bottle-green glass disc carrying the icon's three-stop greens,
/// a diagonal sheen, and a crisp rim, with the negative-space bird **cut out** of
/// the disc so the room shows through it. The old composition punched the cutout
/// to solid black (ledger §9.2); here the bird region is erased with
/// `.destinationOut` inside a `compositingGroup`, so whatever paper sits behind
/// the mark reads through the wings.
///
/// **The Mark Stays Whole:** it renders only as the complete glass mark, never
/// disc-only or wing-curve chrome, and never below the 28pt honesty floor — its
/// home size is 40pt. The glass keeps its icon greens **unchanged at night**.
struct SunbirdColophon: View {
    var diameter: CGFloat = 40

    private var bodyGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Theme.Paint.colophonGlassTop, location: 0),
                .init(color: Theme.Paint.colophonGlassMid, location: 0.46),
                .init(color: Theme.Paint.colophonGlassBottom, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The crisp light-glass rim (SVG `rim`): bright at the crown, faint mid, soft
    /// again at the foot.
    private var rimGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.95), location: 0),
                .init(color: .white.opacity(0.25), location: 0.55),
                .init(color: .white.opacity(0.55), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The diagonal top-light sheen (SVG `sheen`), brightest at the crown.
    private var sheen: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.30), location: 0),
                .init(color: .white.opacity(0.05), location: 0.4),
                .init(color: .clear, location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottom
        )
        .clipShape(Circle())
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(bodyGradient)

            sheen

            Circle()
                .strokeBorder(rimGradient, lineWidth: max(1, diameter * 0.025))

            // Punch the negative-space bird out of the finished glass so the paper
            // behind the mark shows through the wings — never a black fill.
            SunbirdCutoutShape()
                .fill(Color.black)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: diameter, height: diameter)
        // Light-glass physics (#370): a soft drop shadow lifts the disc off the paper.
        .shadow(color: .black.opacity(0.18), radius: diameter * 0.10, y: diameter * 0.06)
        .accessibilityHidden(true)
    }
}

/// The app icon's negative-space bird path (`appicon-light.svg` `#bird` mask),
/// mapped from the icon's 1024² space onto the drawn disc. The disc is `r396`
/// centered at `(512, 512)` in that space, so the path is scaled by
/// `radius / 396` about the frame's center — keeping the bird's placement inside
/// the disc identical to the shipped icon.
struct SunbirdCutoutShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 230, y: 440))
        path.addCurve(
            to: CGPoint(x: 512, y: 510),
            control1: CGPoint(x: 360, y: 415),
            control2: CGPoint(x: 465, y: 465)
        )
        path.addCurve(
            to: CGPoint(x: 794, y: 440),
            control1: CGPoint(x: 559, y: 465),
            control2: CGPoint(x: 664, y: 415)
        )
        path.addCurve(
            to: CGPoint(x: 512, y: 592),
            control1: CGPoint(x: 686, y: 470),
            control2: CGPoint(x: 592, y: 518)
        )
        path.addCurve(
            to: CGPoint(x: 230, y: 440),
            control1: CGPoint(x: 432, y: 518),
            control2: CGPoint(x: 338, y: 470)
        )
        path.closeSubpath()

        let radius = min(rect.width, rect.height) / 2
        let scale = radius / 396
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -512, y: -512)
        return path.applying(transform)
    }
}

#Preview("Sunbird colophon on paper") {
    ZStack {
        Theme.palette(for: .day).gradient.ignoresSafeArea()
        SunbirdColophon(diameter: 120)
    }
}
