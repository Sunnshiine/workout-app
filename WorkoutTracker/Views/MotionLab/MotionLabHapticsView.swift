import SwiftUI

/// The four-word haptic vocabulary (#421), felt in isolation. The RPE strip is a
/// stand-in detent surface — drag across it to feel the half-point ticks with the
/// thumb, eyes off the screen. Tunings ride the variant switcher.
struct MotionLabHapticsView: View {
    let tuning: MotionLabHapticTuning
    let ceremony: MotionLabCeremonyVariant
    let haptics: MotionLabHaptics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            rpeCard
            wordCard(
                title: "Log Set — one firm tap",
                detail: transientLabel(tuning.log),
                systemImage: "checkmark.circle"
            ) {
                haptics.logTap(tuning)
            }
            wordCard(
                title: "Skip — one soft dud",
                detail: transientLabel(tuning.skip),
                systemImage: "arrow.right.to.line"
            ) {
                haptics.skipDud(tuning)
            }
            wordCard(
                title: "Move On — the one rich pattern",
                detail: "timed to ceremony \(ceremony.id) · \(ceremony.name)",
                systemImage: "bird"
            ) {
                haptics.moveOn(tuning, ceremony: ceremony)
            }
            Text("Chrome is silent: nothing here fires on plain buttons or form fields — only the four words speak.")
                .font(.caption)
                .foregroundStyle(MotionLabInk.muted)
        }
        .padding(20)
    }

    private var rpeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RPE — half-point detent ticks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MotionLabInk.ink)
            MotionLabRPEStrip(tuning: tuning, haptics: haptics)
            Text(transientLabel(tuning.tick))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(MotionLabInk.muted)
        }
        .padding(16)
        .background(MotionLabInk.cream.opacity(0.6), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(MotionLabInk.ink.opacity(0.08)))
    }

    private func wordCard(
        title: String,
        detail: String,
        systemImage: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(MotionLabInk.action)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MotionLabInk.ink)
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(MotionLabInk.muted)
                }
                Spacer()
                Image(systemName: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(MotionLabInk.muted)
            }
            .padding(16)
            .background(MotionLabInk.cream.opacity(0.6), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MotionLabInk.ink.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func transientLabel(_ t: MotionLabHapticTuning.Transient) -> String {
        String(format: "intensity %.2f · sharpness %.2f", t.intensity, t.sharpness)
    }
}

/// A draggable strip with nine half-point detents (6.0 … 10.0). Crossing a detent
/// fires exactly one tick — the increments communicated through the thumb.
struct MotionLabRPEStrip: View {
    let tuning: MotionLabHapticTuning
    let haptics: MotionLabHaptics

    @State private var detent = 4

    private let thumbSize: CGFloat = 30

    var body: some View {
        VStack(spacing: 10) {
            Text(String(format: "%.1f", value))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MotionLabInk.ink)

            GeometryReader { proxy in
                let width = proxy.size.width
                let usable = width - thumbSize
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MotionLabInk.cream)
                        .overlay(Capsule().stroke(MotionLabInk.action.opacity(0.3), lineWidth: 1))
                        .frame(height: 10)
                        .padding(.horizontal, thumbSize / 2)
                    ForEach(0..<9) { index in
                        Circle()
                            .fill(MotionLabInk.action.opacity(index == detent ? 0.9 : 0.3))
                            .frame(width: 4, height: 4)
                            .offset(x: thumbSize / 2 + usable * CGFloat(index) / 8 - 2)
                    }
                    Circle()
                        .fill(MotionLabInk.action)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: usable * CGFloat(detent) / 8)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            update(x: gesture.location.x, usable: usable)
                        }
                )
            }
            .frame(height: 44)
        }
    }

    private var value: Double {
        6 + Double(detent) / 2
    }

    private func update(x: CGFloat, usable: CGFloat) {
        guard usable > 0 else { return }
        let fraction = min(max((x - thumbSize / 2) / usable, 0), 1)
        let next = Int((fraction * 8).rounded())
        guard next != detent else { return }
        detent = next
        haptics.tick(tuning)
    }
}
