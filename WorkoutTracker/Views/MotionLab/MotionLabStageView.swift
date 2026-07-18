import SwiftUI

/// The living stage, mocked at real density: Cadence line, serif Exercise name,
/// the branch, the Active Set Card, and Log/Skip on stock chrome (#421 — the
/// capsule stays humble; feedback is the leaf above plus the haptic in the hand).
struct MotionLabStageView: View {
    let variant: MotionLabStageVariant
    let tuning: MotionLabHapticTuning
    let reduceMotion: Bool
    let haptics: MotionLabHaptics

    @State private var nodes = MotionLabSetNode.fiveSetStage
    @State private var run: MotionLabStageRun?

    private let stem = MotionLabStem.stage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            branch
            activeCard
            controls
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cadence 3 · 1 · X · 1")
                .font(.footnote)
                .foregroundStyle(MotionLabInk.muted)
            Text("Competition Back Squat")
                .font(.system(size: 30, weight: .medium, design: .serif))
                .foregroundStyle(MotionLabInk.ink)
        }
    }

    private var branch: some View {
        TimelineView(.animation(minimumInterval: nil, paused: run == nil)) { timeline in
            ZStack(alignment: .topLeading) {
                MotionLabStemShape(stem: stem)
                    .stroke(MotionLabInk.stem, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ForEach(nodes) { node in
                    MotionLabLeafNodeView(
                        node: node,
                        stem: stem,
                        channels: MotionLabStageChannels.resolve(
                            node: node,
                            run: run,
                            variant: variant,
                            reduceMotion: reduceMotion,
                            now: timeline.date
                        )
                    )
                }
            }
            .frame(width: 329, height: 148)
        }
        .frame(maxWidth: .infinity)
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(cardHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MotionLabInk.ink)
                Spacer()
                Text("W1 D2 — 90×5 @8")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(MotionLabInk.muted)
            }
            HStack(spacing: 10) {
                valuePill("92.5 kg")
                valuePill("5 reps")
                valuePill("@ 8")
            }
        }
        .padding(16)
        .background(MotionLabInk.cream.opacity(0.6), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(MotionLabInk.ink.opacity(0.08)))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if currentIndex == nil {
                Button {
                    nodes = MotionLabSetNode.fiveSetStage
                } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(MotionLabInk.muted)
            } else {
                Button("Skip") {
                    start(.skip)
                }
                .buttonStyle(.bordered)
                .tint(MotionLabInk.muted)
                .disabled(run != nil)

                Button {
                    start(.log)
                } label: {
                    Text("Log Set")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MotionLabInk.action)
                .disabled(run != nil)
            }
        }
    }

    private var currentIndex: Int? {
        nodes.firstIndex { $0.state == .current }
    }

    private var cardHeadline: String {
        guard let index = currentIndex else { return "Session complete" }
        return "Set \(index + 1) of \(nodes.count)"
    }

    private func valuePill(_ label: String) -> some View {
        Text(label)
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(MotionLabInk.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(MotionLabInk.cream, in: .capsule)
            .overlay(Capsule().stroke(MotionLabInk.action.opacity(0.35), lineWidth: 1))
    }

    private func start(_ kind: MotionLabStageRun.Kind) {
        guard run == nil, let index = currentIndex else { return }
        let next = nodes.firstIndex { $0.state == .future }
        switch kind {
        case .log:
            haptics.logTap(tuning)
        case .skip:
            haptics.skipDud(tuning)
        }
        let active = MotionLabStageRun(
            kind: kind,
            start: .now,
            nodeID: nodes[index].id,
            nextID: next.map { nodes[$0].id }
        )
        run = active
        let total = reduceMotion ? 0.45 : variant.total
        Task {
            try? await Task.sleep(for: .seconds(total + 0.05))
            finish(active)
        }
    }

    private func finish(_ active: MotionLabStageRun) {
        guard run?.start == active.start else { return }
        if let index = nodes.firstIndex(where: { $0.id == active.nodeID }) {
            nodes[index].state = active.kind == .log ? .logged : .skipped
        }
        if let nextID = active.nextID, let index = nodes.firstIndex(where: { $0.id == nextID }) {
            nodes[index].state = .current
        }
        run = nil
    }
}

struct MotionLabStageRun {
    enum Kind {
        case log
        case skip
    }

    let kind: Kind
    let start: Date
    let nodeID: Int
    let nextID: Int?
}

/// Turns committed Set state plus the active run clock into render channels.
enum MotionLabStageChannels {
    static func resolve(
        node: MotionLabSetNode,
        run: MotionLabStageRun?,
        variant: MotionLabStageVariant,
        reduceMotion: Bool,
        now: Date
    ) -> MotionLabLeafChannels {
        var channels = MotionLabLeafChannels()
        switch node.state {
        case .logged:
            channels.leafInk = 1
        case .skipped:
            channels.skipDraw = 1
        case .current:
            channels.budPresence = 1
        case .future:
            channels.futureAlpha = 1
        }
        guard let run else { return channels }
        let elapsed = now.timeIntervalSince(run.start)

        if node.id == run.nodeID {
            channels = MotionLabLeafChannels()
            if reduceMotion {
                // crossfade only — same end state, zero kinetics (#421)
                let fade = WingEase.phase(elapsed, start: 0, duration: 0.4)
                channels.budPresence = 1 - fade
                channels.leafAlpha = fade
                if run.kind == .log { channels.leafInk = 1 } else { channels.skipDraw = 1 }
            } else {
                let draw = WingEase.eased(WingEase.phase(elapsed, start: 0, duration: variant.inkDuration))
                if run.kind == .log {
                    channels.leafInk = draw
                    channels.budPresence = max(0, 1 - draw * 1.8)
                } else {
                    channels.skipDraw = draw
                    channels.budPresence = max(0, 1 - draw * 2.5)
                }
            }
        }

        if node.id == run.nextID {
            channels = MotionLabLeafChannels()
            if reduceMotion {
                let fade = WingEase.phase(elapsed, start: 0, duration: 0.4)
                channels.futureAlpha = 1 - fade
                channels.budPresence = fade
            } else {
                let open = WingEase.eased(
                    WingEase.phase(elapsed, start: variant.budDelay, duration: variant.budDuration)
                )
                channels.futureAlpha = 1 - open
                channels.budPresence = open
                channels.budScale = budScale(open: open, overshoot: variant.budOvershoot)
            }
        }
        return channels
    }

    private static func budScale(open: Double, overshoot: Bool) -> Double {
        guard open > 0 else { return 1 }
        guard overshoot else { return 0.6 + 0.4 * open }
        if open < 0.75 { return 0.6 + 0.48 * (open / 0.75) }
        return 1.08 - 0.08 * ((open - 0.75) / 0.25)
    }
}
