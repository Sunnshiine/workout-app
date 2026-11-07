import AVFoundation
import SwiftUI
import UIKit

/// The frame itself, at its own shape, with the Bar Path drawn over it.
struct FormClipSurface: View {
    let player: ClipPlayer
    let path: BarPath?
    let isPathShown: Bool
    var onTap: ((CGPoint) -> Void)?  // default: no tap, the answer on every frame but the one awaiting the plate
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack {
            if let still = player.still {
                Image(decorative: still, scale: 1).resizable()
            } else {
                PlayerLayerView(player: player.player)
            }
            if let path, isPathShown {
                BarPathOverlay(path: path, player: player)
                    .transition(.opacity)
            }
            if let onTap {
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { location in
                            onTap(
                                CGPoint(
                                    x: location.x / geometry.size.width,
                                    y: location.y / geometry.size.height
                                )
                            )
                        }
                }
                .accessibilityElement()
                .accessibilityLabel("The frame")
                .accessibilityHint("Touch the center of the plate")
                .accessibilityDirectTouch()
                .accessibilityIdentifier("form-clip-plate-target")
                .transition(.opacity)
            }
        }
        .aspectRatio(player.aspect ?? 9.0 / 16.0, contentMode: .fit)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay {
            // The frame itself is the control while it waits for the plate, so it says so.
            if onTap != nil {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(palette.action, lineWidth: 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: isPathShown ? 0.2 : 0.15), value: isPathShown)
        .animation(.easeOut(duration: onTap == nil ? 0.15 : 0.2), value: onTap == nil)
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PlayerSurfaceView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
    }

    final class PlayerSurfaceView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        // swiftlint:disable:next force_cast
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// The plate's path in action green, because it is progress that actually happened: the whole line
/// quiet, the part already travelled at full ink, and where the plate is now.
private struct BarPathOverlay: View {
    let path: BarPath
    let player: ClipPlayer
    @Environment(\.themePalette) private var palette

    var body: some View {
        Canvas { context, size in
            let time = player.time
            func line(_ samples: some Sequence<BarPath.Sample>) -> Path {
                var drawn = Path()
                for sample in samples {
                    let point = CGPoint(x: sample.x * size.width, y: sample.y * size.height)
                    if drawn.isEmpty { drawn.move(to: point) } else { drawn.addLine(to: point) }
                }
                return drawn
            }
            let whole = line(path.samples)
            let shape = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            let casing = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
            context.stroke(whole, with: .color(palette.paper.baseBottom.opacity(0.5)), style: casing)
            context.stroke(whole, with: .color(palette.action.opacity(0.4)), style: shape)
            context.stroke(line(path.travelled(upTo: time)), with: .color(palette.action), style: shape)
            if let now = path.position(at: time) {
                let center = CGPoint(x: now.x * size.width, y: now.y * size.height)
                let outer = CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: outer), with: .color(palette.paper.baseBottom.opacity(0.6)))
                context.fill(Path(ellipseIn: outer.insetBy(dx: 2, dy: 2)), with: .color(palette.action))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
