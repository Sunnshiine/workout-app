import SwiftUI

/// The Move On ceremony entry: stem grows, leaves pop as it passes, the bird
/// arrives at the tip, then the day's numbers fade in. The one rich haptic
/// pattern plays timed to the pacing (#421 — identical every time).
struct MotionLabCeremonyView: View {
    let variant: MotionLabCeremonyVariant
    let tuning: MotionLabHapticTuning
    let reduceMotion: Bool
    let haptics: MotionLabHaptics

    @State private var runStart: Date?
    @State private var isSettled = false

    private let stem = MotionLabStem.ceremony
    private let nodes = MotionLabSetNode.fourteenCeremony

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Block 27 · Week 2 · Day 2")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MotionLabInk.ink)
                Spacer()
                Text("Move On")
                    .font(.footnote)
                    .foregroundStyle(MotionLabInk.muted)
            }

            Spacer(minLength: 20)

            Text("Day 2, done.")
                .font(.system(size: 36, weight: .medium, design: .serif))
                .foregroundStyle(MotionLabInk.ink)

            growth
                .padding(.top, 12)

            Spacer(minLength: 20)

            Button {
                start()
            } label: {
                Text(runStart == nil ? "Move On" : "Replay")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MotionLabInk.action)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 560)
    }

    private var growth: some View {
        TimelineView(.animation(minimumInterval: nil, paused: runStart == nil || isSettled)) { timeline in
            let frame = currentFrame(at: timeline.date)
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    MotionLabStemShape(stem: stem)
                        .trim(from: 0, to: frame.stemTrim)
                        .stroke(MotionLabInk.stem, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    ForEach(nodes) { node in
                        MotionLabLeafNodeView(
                            node: node,
                            stem: stem,
                            channels: leafChannels(node: node, at: timeline.date)
                        )
                    }
                    bird(frame)
                }
                .opacity(frame.wholeAlpha)
                .frame(width: 321, height: 232)

                Text("Bench 92.5 × 5 @8 topped last week's 90.")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(MotionLabInk.muted)
                    .padding(.top, 12)
                    .opacity(frame.reveal)

                statsRow
                    .padding(.top, 14)
                    .opacity(frame.reveal)
            }
        }
    }

    private func bird(_ frame: MotionLabCeremonyFrame) -> some View {
        ZStack(alignment: .topLeading) {
            MotionLabBirdShape()
                .fill(MotionLabInk.birdFill)
            MotionLabBirdRibShape()
                .stroke(MotionLabInk.birdRib, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .opacity(frame.birdOpacity)
        .transformEffect(birdTransform(frame))
    }

    /// The bird perches at the stem tip, leaned with the branch (-8°, #414).
    private func birdTransform(_ frame: MotionLabCeremonyFrame) -> CGAffineTransform {
        var t = CGAffineTransform(
            translationX: stem.end.x + frame.birdOffset.width,
            y: stem.end.y + frame.birdOffset.height
        )
        t = t.rotated(by: -8 * .pi / 180)
        return t
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCell("14", "Sets")
            statCell("4", "Exercises")
            statCell("0", "Left")
        }
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MotionLabInk.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(MotionLabInk.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(MotionLabInk.cream.opacity(0.55), in: .rect(cornerRadius: 12))
    }

    private func currentFrame(at date: Date) -> MotionLabCeremonyFrame {
        guard let runStart else { return MotionLabCeremonyFrame() }
        return MotionLabCeremonyFrame.resolve(
            elapsed: date.timeIntervalSince(runStart),
            variant: variant,
            reduceMotion: reduceMotion
        )
    }

    private func leafChannels(node: MotionLabSetNode, at date: Date) -> MotionLabLeafChannels {
        var channels = MotionLabLeafChannels()
        channels.leafInk = 1
        guard let runStart else {
            channels.leafAlpha = 0
            return channels
        }
        let elapsed = date.timeIntervalSince(runStart)
        if reduceMotion {
            channels.leafAlpha = WingEase.phase(elapsed, start: 0, duration: 0.45)
            return channels
        }
        // each leaf pops as the growing stem tip passes its position
        let startTime = variant.stemDuration * WingEase.inverseEased(Double(node.t))
        let pop = WingEase.eased(WingEase.phase(elapsed, start: startTime, duration: variant.leafPop))
        channels.leafAlpha = pop
        channels.pop = 0.25 + 0.75 * pop
        return channels
    }

    private func start() {
        let begin = Date.now
        runStart = begin
        isSettled = false
        // haptics are unaffected by reduced motion (#421) — same pattern either way
        haptics.moveOn(tuning, ceremony: variant)
        let total = reduceMotion ? 0.9 : variant.total + 0.8
        Task {
            try? await Task.sleep(for: .seconds(total))
            if runStart == begin { isSettled = true }
        }
    }
}

/// Per-frame ceremony channels outside the per-leaf ones.
struct MotionLabCeremonyFrame {
    var stemTrim: Double = 0
    var birdOpacity: Double = 0
    var birdOffset: CGSize = .zero
    var reveal: Double = 0
    var wholeAlpha: Double = 1

    static func resolve(
        elapsed: Double,
        variant: MotionLabCeremonyVariant,
        reduceMotion: Bool
    ) -> MotionLabCeremonyFrame {
        var frame = MotionLabCeremonyFrame()
        if reduceMotion {
            // the ceremony fades in as one fully-grown frame (#421)
            let fade = WingEase.phase(elapsed, start: 0, duration: 0.45)
            frame.stemTrim = 1
            frame.wholeAlpha = fade
            frame.birdOpacity = fade
            frame.reveal = WingEase.phase(elapsed, start: 0.3, duration: 0.4)
            return frame
        }
        frame.stemTrim = WingEase.eased(WingEase.phase(elapsed, start: 0, duration: variant.stemDuration))
        let arrive = WingEase.eased(
            WingEase.phase(elapsed, start: variant.birdStart, duration: variant.birdDuration)
        )
        frame.birdOpacity = arrive
        frame.birdOffset =
            variant.birdGlides
            ? CGSize(width: 26 * (1 - arrive), height: -20 * (1 - arrive))
            : CGSize(width: 0, height: -14 * (1 - arrive))
        frame.reveal = WingEase.phase(
            elapsed,
            start: variant.birdStart + variant.birdDuration * 0.6,
            duration: 0.45
        )
        return frame
    }
}
