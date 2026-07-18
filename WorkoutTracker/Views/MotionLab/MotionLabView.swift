import SwiftUI

/// Throwaway device-feel lab for #452. Three moments — the living stage, the Move
/// On ceremony, and the haptic vocabulary — each with three switchable variants.
/// The black pill switcher is lab chrome, deliberately not part of the design
/// under review. Never merges; dies with the prototype PR.
struct MotionLabView: View {
    private enum Moment: String, CaseIterable, Identifiable {
        case stage = "Stage"
        case ceremony = "Ceremony"
        case haptics = "Haptics"

        var id: String { rawValue }
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var moment = Moment.stage
    @State private var stageIndex = 0
    @State private var ceremonyIndex = 0
    @State private var hapticsIndex = 0
    @State private var forceReduceMotion = false
    @State private var haptics = MotionLabHaptics()

    var body: some View {
        ZStack {
            MotionLabPaper()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    Picker("Moment", selection: $moment) {
                        ForEach(Moment.allCases) { moment in
                            Text(moment.rawValue).tag(moment)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $forceReduceMotion) {
                        Text("Force Reduce Motion")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MotionLabInk.ink)
                    }
                    .tint(MotionLabInk.action)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(MotionLabInk.cream.opacity(0.5), in: .rect(cornerRadius: 12))

                    Text(variantBlurb)
                        .font(.footnote)
                        .foregroundStyle(MotionLabInk.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    content
                        .background(MotionLabInk.cream.opacity(0.25), in: .rect(cornerRadius: 20))
                }
                .padding()
                .padding(.bottom, 96)
            }
        }
        .navigationTitle("Motion Lab")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            switcher
                .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var content: some View {
        let reduce = systemReduceMotion || forceReduceMotion
        switch moment {
        case .stage:
            MotionLabStageView(
                variant: stageVariant,
                tuning: hapticTuning,
                reduceMotion: reduce,
                haptics: haptics
            )
            .id("stage-\(stageVariant.id)-\(reduce)")
        case .ceremony:
            MotionLabCeremonyView(
                variant: ceremonyVariant,
                tuning: hapticTuning,
                reduceMotion: reduce,
                haptics: haptics
            )
            .id("ceremony-\(ceremonyVariant.id)-\(reduce)")
        case .haptics:
            MotionLabHapticsView(
                tuning: hapticTuning,
                ceremony: ceremonyVariant,
                haptics: haptics
            )
        }
    }

    private var switcher: some View {
        HStack(spacing: 18) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            Text(switcherLabel)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 150)
            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .foregroundStyle(.white)
        .background(.black.opacity(0.82), in: .capsule)
    }

    private var stageVariant: MotionLabStageVariant {
        MotionLabStageVariant.all[stageIndex]
    }

    private var ceremonyVariant: MotionLabCeremonyVariant {
        MotionLabCeremonyVariant.all[ceremonyIndex]
    }

    private var hapticTuning: MotionLabHapticTuning {
        MotionLabHapticTuning.all[hapticsIndex]
    }

    private var switcherLabel: String {
        switch moment {
        case .stage:
            "\(stageVariant.id) · \(stageVariant.name)"
        case .ceremony:
            "\(ceremonyVariant.id) · \(ceremonyVariant.name)"
        case .haptics:
            "\(hapticTuning.id) · \(hapticTuning.name)"
        }
    }

    private var variantBlurb: String {
        switch moment {
        case .stage:
            stageVariant.blurb
        case .ceremony:
            ceremonyVariant.blurb
        case .haptics:
            hapticTuning.blurb
        }
    }

    private func step(_ delta: Int) {
        switch moment {
        case .stage:
            stageIndex = wrapped(stageIndex + delta, count: MotionLabStageVariant.all.count)
        case .ceremony:
            ceremonyIndex = wrapped(ceremonyIndex + delta, count: MotionLabCeremonyVariant.all.count)
        case .haptics:
            hapticsIndex = wrapped(hapticsIndex + delta, count: MotionLabHapticTuning.all.count)
        }
    }

    private func wrapped(_ value: Int, count: Int) -> Int {
        ((value % count) + count) % count
    }
}
