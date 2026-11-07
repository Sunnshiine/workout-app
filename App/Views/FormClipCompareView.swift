import SwiftUI

/// Two clips of a Movement side by side, opening on the previous one, or a plain word when there
/// is nothing yet to compare.
struct FormClipCompareView: View {
    let clip: FormClip
    /// Add Clip when there is nothing beside this one. Nil where there is no Set card to return to.
    let onAdd: ((FormClipSource) -> Void)?
    let onClose: () -> Void
    @Environment(FormClipLibrary.self) private var library
    @Environment(WorkoutStore.self) private var workout
    @State private var chosen: UUID?

    var body: some View {
        let left = library.clip(clip.id) ?? clip
        Group {
            if let right = chosen.flatMap(library.clip) ?? library.previous(of: left) {
                FormClipCompareLoader(
                    left: left,
                    right: right,
                    leftFacts: left.facts(in: workout.block),
                    rightFacts: right.facts(in: workout.block),
                    leftMovie: library.url(of: left),
                    rightMovie: library.url(of: right),
                    choices: library.comparable(with: left),
                    onChoose: { chosen = $0 },
                    onClose: onClose
                )
                .id(right.id)
            } else {
                FormClipCompareEmpty(name: left.snapshotFacts.exerciseName, onAdd: onAdd, onClose: onClose)
            }
        }
        .formClipRoom()
    }
}

/// Holds the two players for as long as this pair is on screen, built once as the screen appears.
private struct FormClipCompareLoader: View {
    let left: FormClip
    let right: FormClip
    let leftFacts: FormClipFacts
    let rightFacts: FormClipFacts
    let leftMovie: URL
    let rightMovie: URL
    let choices: [FormClip]
    let onChoose: (UUID) -> Void
    let onClose: () -> Void
    @Environment(\.themePalette) private var palette
    @State private var comparison: ClipComparison?

    var body: some View {
        ZStack {
            palette.paperBackground.ignoresSafeArea()
            if let comparison {
                FormClipCompareScreen(
                    left: left,
                    right: right,
                    leftFacts: leftFacts,
                    rightFacts: rightFacts,
                    comparison: comparison,
                    choices: choices,
                    onChoose: onChoose,
                    onClose: onClose
                )
            }
        }
        .onAppear {
            if let comparison {
                comparison.setUp()
                return
            }
            comparison = ClipComparison(
                left: ClipPlayer(url: leftMovie, duration: left.duration),
                right: ClipPlayer(url: rightMovie, duration: right.duration),
                leftStart: left.effectiveStart,
                rightStart: right.effectiveStart
            )
        }
    }
}

struct FormClipCompareEmpty: View {
    let name: String
    let onAdd: ((FormClipSource) -> Void)?
    let onClose: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            Text("No other clip of \(name)")
                .themeFont(.sheetTitle)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text("Add another clip of this Movement, and it opens here beside this one.")
                .themeFont(.coachNote)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            if let onAdd {
                Menu {
                    if FormClipCamera.isAvailable {
                        Button("Record Clip") { onAdd(.camera) }
                    }
                    Button("Add Clip") { onAdd(.photos) }
                } label: {
                    Image(systemName: "video.badge.plus")
                        .themeFont(.logCapsule)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(palette.textPrimary)
                .padding(.top, 4)
                .accessibilityLabel("Add Clip")
                .accessibilityIdentifier("form-clip-compare-add")
            }
        }
        .padding(Theme.cardSpacing * 2)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .padding(.horizontal, Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            ClipGlyphToggle(glyph: "xmark", label: "Close", id: "form-clip-compare-close", isOn: false, onTap: onClose)
                .padding(.leading, Theme.pageMargin - 12)
        }
        .background { palette.paperBackground.ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("form-clip-compare-empty")
    }
}

struct FormClipCompareScreen: View {
    let left: FormClip
    let right: FormClip
    let leftFacts: FormClipFacts
    let rightFacts: FormClipFacts
    let comparison: ClipComparison
    let choices: [FormClip]
    let onChoose: (UUID) -> Void
    let onClose: () -> Void
    @Environment(FormClipLibrary.self) private var library
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.themePalette) private var palette
    @State private var isMarkFailed = false

    private var statusLine: String? {
        if isMarkFailed { return "That mark couldn't be saved. Try it again." }
        return left.startMark != nil && right.startMark != nil ? nil : "Drag each clip to where its Set starts, then tap its flag."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ClipGlyphToggle(glyph: "xmark", label: "Close", id: "form-clip-compare-close", isOn: false, onTap: onClose)
                    .padding(.leading, -12)
                Text(leftFacts.exerciseName)
                    .themeFont(.sheetTitle)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 8) {
                pane(.left, clip: left, facts: leftFacts)
                pane(.right, clip: right, facts: rightFacts)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .layoutPriority(-1)

            Text(statusLine ?? " ")
                .themeFont(.runlineSecondary)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(Theme.TypeRole.runlineSecondary.denseFloorScale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("form-clip-compare-status")
                .accessibilityHidden(statusLine == nil)

            CompareFoot(comparison: comparison)
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.bottom, 8)
        .background { palette.paperBackground.ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("form-clip-compare")
        .accessibilityAction(.escape, onClose)
        .onDisappear(perform: comparison.tearDown)
    }

    private func pane(_ pane: ClipComparison.Pane, clip: FormClip, facts: FormClipFacts) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            paneHeading(pane, facts: facts)

            FormClipSurface(player: comparison.player(for: pane), path: clip.barPath, isPathShown: true)
                .frame(maxWidth: .infinity, alignment: .top)
                .modifier(PaneScrub(comparison: comparison, pane: pane, onClose: onClose))
                .accessibilityLabel(pane == .left ? "This clip" : "The clip beside it")
                .accessibilityValue(facts.line)
                .accessibilityIdentifier(pane == .left ? "form-clip-pane-left" : "form-clip-pane-right")

            markButton(pane, clip: clip)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The left clip names the Block both are read against, so only another Block's clip spells its.
    @ViewBuilder
    private func paneHeading(_ pane: ClipComparison.Pane, facts: FormClipFacts) -> some View {
        let text = VStack(alignment: .leading, spacing: 2) {
            Text(facts.placement(beside: leftFacts.setID.session.blockTab))
                .themeFont(.runline)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.head)
                .minimumScaleFactor(Theme.TypeRole.runline.denseFloorScale)
            Text(facts.logged.label)
                .themeFont(.runlineSecondary)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(Theme.TypeRole.runlineSecondary.denseFloorScale)
        }
        if pane == .right, choices.count > 1 {
            Menu {
                ForEach(choices) { choice in
                    Button(choice.facts(in: workout.block).placement(beside: leftFacts.setID.session.blockTab)) {
                        onChoose(choice.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    text
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityLabel("Choose the clip beside it")
            .accessibilityValue(facts.line)
            .accessibilityIdentifier("form-clip-compare-choose")
        } else {
            text.frame(minHeight: 44, alignment: .leading)
        }
    }

    private func markButton(_ pane: ClipComparison.Pane, clip: FormClip) -> some View {
        ClipGlyphToggle(
            glyph: clip.startMark == nil ? "flag" : "flag.fill",
            label: "Mark this frame as the Set's start",
            id: pane == .left ? "form-clip-mark-left" : "form-clip-mark-right",
            isOn: clip.startMark != nil
        ) {
            HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
            do {
                try library.setStartMark(comparison.markStart(pane), on: clip.id)
                isMarkFailed = false
            } catch {
                isMarkFailed = true
            }
        }
        .padding(.leading, -12)
    }
}

/// A drag across a pane moves that movie alone, the whole clip across the pane's width, each half
/// second ticking under the thumb. A drag that starts downward pulls the pane to close Compare
/// instead. VoiceOver swipes it a second at a time.
private struct PaneScrub: ViewModifier {
    let comparison: ClipComparison
    let pane: ClipComparison.Pane
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grabbedAt: Double?
    @State private var pulled: Double?
    @State private var width = 1.0

    func body(content: Content) -> some View {
        let player = comparison.player(for: pane)
        content
            .onGeometryChange(for: Double.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .offset(y: reduceMotion ? 0 : pulled ?? 0)
            .animation(Theme.pressAnimation, value: pulled == nil)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let moved = value.translation
                        if grabbedAt == nil, pulled == nil {
                            if ClipCloseDrag.isDownward(width: moved.width, height: moved.height) {
                                pulled = moved.height
                            } else {
                                grabbedAt = player.time
                            }
                        }
                        guard let grabbed = grabbedAt else {
                            pulled = max(moved.height, 0)
                            return
                        }
                        let target = ClipScrubDetent.time(
                            grabbedAt: grabbed,
                            moved: moved.width,
                            across: width,
                            in: 0...player.duration
                        )
                        if ClipScrubDetent.crossed(from: player.time, to: target) {
                            HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
                        }
                        comparison.scrub(pane, to: target)
                    }
                    .onEnded { value in
                        if pulled != nil, ClipCloseDrag.closes(width: value.translation.width, height: value.translation.height) {
                            onClose()
                        }
                        grabbedAt = nil
                        pulled = nil
                    }
            )
            .accessibilityElement()
            .accessibilityAdjustableAction { direction in
                comparison.scrub(pane, to: player.time + (direction == .increment ? 1 : -1))
            }
    }
}

private struct CompareFoot: View {
    let comparison: ClipComparison

    var body: some View {
        VStack(spacing: 8) {
            ClipScrubber(
                time: comparison.sharedTime,
                range: comparison.timeline.span,
                onBegan: comparison.beginScrub,
                onChanged: comparison.scrub(to:),
                onEnded: {}
            )

            ClipPlayRow(isPlaying: comparison.isPlaying, onToggle: comparison.togglePlaying, onStep: comparison.step(by:))

            HStack(spacing: 0) {
                ClipRateRail(rate: comparison.rate, onSelect: comparison.setRate)
                Spacer(minLength: 4)
                ClipGlyphToggle(glyph: "repeat", label: "Loop", id: "form-clip-compare-loop", isOn: comparison.loops) {
                    comparison.loops.toggle()
                }
                .padding(.trailing, -9)
            }
        }
    }
}
