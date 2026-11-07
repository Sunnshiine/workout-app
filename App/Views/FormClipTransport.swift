import SwiftUI

/// The clip's scrubber. A drag moves the playhead by how far the finger travels, not to where it
/// landed, so a touch never jumps the frame the athlete is looking at. It ticks at each detent.
struct ClipScrubber: View {
    let time: Double
    let range: ClosedRange<Double>
    let onBegan: () -> Void
    let onChanged: (Double) -> Void
    let onEnded: () -> Void
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var grabbedAt: Double?

    private var span: Double { max(range.upperBound - range.lowerBound, 0.001) }

    private var share: Double { min(max((time - range.lowerBound) / span, 0), 1) }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.pillStroke).frame(height: 4)
                    Capsule().fill(palette.textPrimary).frame(width: width * share, height: 4)
                    Circle()
                        .fill(palette.textPrimary)
                        .frame(width: 16, height: 16)
                        .scaleEffect(grabbedAt == nil ? 1 : 1.35)
                        .animation(Theme.pressAnimation, value: grabbedAt == nil)
                        .offset(x: width * share - 8)
                }
                .frame(height: 44)
                .contentShape(.rect)
                .gesture(drag(across: width))
            }
            .frame(height: 44)

            HStack {
                Text(ClipTimeLabel.text(max(time - range.lowerBound, 0)))
                Spacer()
                Text(ClipTimeLabel.text(span))
            }
            .themeFont(.runlineSecondary)
            .monospacedDigit()
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityValue("\(ClipTimeLabel.text(max(time - range.lowerBound, 0))) of \(ClipTimeLabel.text(span))")
        .accessibilityAdjustableAction { direction in
            onBegan()
            onChanged(min(max(time + (direction == .increment ? 1 : -1), range.lowerBound), range.upperBound))
            onEnded()
        }
        .accessibilityIdentifier("form-clip-scrubber")
    }

    private func drag(across width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if grabbedAt == nil {
                    grabbedAt = time
                    onBegan()
                }
                let target = ClipScrubDetent.time(
                    grabbedAt: grabbedAt ?? time,
                    moved: value.translation.width,
                    across: width,
                    in: range
                )
                if ClipScrubDetent.crossed(from: time, to: target) {
                    HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
                }
                onChanged(target)
            }
            .onEnded { _ in
                grabbedAt = nil
                onEnded()
            }
    }
}

/// Frame step and play: the three controls under the thumb, the same in a review and a Compare.
struct ClipPlayRow: View {
    let isPlaying: Bool
    let onToggle: () -> Void
    let onStep: (Int) -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 28) {
            stepButton("backward.frame.fill", label: "Back one frame", id: "form-clip-step-back", frames: -1)

            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .themeFont(.logCapsule)
                    .imageScale(.large)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 60, height: 60)
                    .background(palette.footFill, in: .circle)
                    .themeElevation(palette.lighting.raisedControlShadow, in: Circle())
                    .contentShape(.circle)
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("form-clip-play")

            stepButton("forward.frame.fill", label: "Forward one frame", id: "form-clip-step-forward", frames: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ glyph: String, label: String, id: String, frames: Int) -> some View {
        Button {
            HapticPlayer.shared.play(.input(Theme.Haptics.stepperTick))
            onStep(frames)
        } label: {
            Image(systemName: glyph)
                .imageScale(.large)
                .foregroundStyle(palette.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// The review's speeds, laid in a rail the way the card's rails sit, the current one lit.
struct ClipRateRail: View {
    let rate: ClipPlaybackRate
    let onSelect: (ClipPlaybackRate) -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ClipPlaybackRate.allCases, id: \.self) { candidate in
                Button {
                    HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
                    onSelect(candidate)
                } label: {
                    Text(candidate.label)
                        .themeFont(.queuePill)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            if candidate == rate {
                                RoundedRectangle(cornerRadius: Theme.Radius.cell)
                                    .fill(palette.railSelectedFill)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Theme.Radius.cell)
                                            .strokeBorder(palette.action, lineWidth: 2)
                                    }
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.accessibilityLabel)
                .accessibilityAddTraits(candidate == rate ? .isSelected : [])
                .accessibilityIdentifier("form-clip-rate-\(candidate.label)")
            }
        }
        .padding(Theme.Radius.rail - Theme.Radius.cell)
        .background(palette.railFill, in: .rect(cornerRadius: Theme.Radius.rail))
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A 44pt glyph control in the review's chrome, in action ink while it is on.
struct ClipGlyphToggle: View {
    let glyph: String
    let label: String
    let id: String
    let isOn: Bool
    let onTap: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: onTap) {
            Image(systemName: glyph)
                .imageScale(.large)
                .foregroundStyle(isOn ? palette.action : palette.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// A movie pulled down leaves the room, so the way out sits under the thumb as well as in the top
/// corner. The movie follows the finger, and falls back if it's let go short.
struct ClipPullToClose: ViewModifier {
    let isEnabled: Bool
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulled = 0.0

    func body(content: Content) -> some View {
        content
            .offset(y: reduceMotion ? 0 : pulled)
            .animation(Theme.pressAnimation, value: pulled == 0)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        let moved = value.translation
                        pulled = ClipCloseDrag.isDownward(width: moved.width, height: moved.height) ? moved.height : 0
                    }
                    .onEnded { value in
                        if ClipCloseDrag.closes(width: value.translation.width, height: value.translation.height) {
                            onClose()
                        } else {
                            pulled = 0
                        }
                    },
                isEnabled: isEnabled
            )
    }
}
