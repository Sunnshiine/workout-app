import AVFoundation
import SwiftUI

extension View {
    /// The review's room: always Night, whatever the app's appearance, because a movie needs a dark
    /// surround, and Night is the app's dark, never a neutral black.
    func formClipRoom() -> some View {
        environment(\.themePalette, Theme.palette(for: .night))
            .preferredColorScheme(.dark)
            .dynamicTypeSize(...Theme.TypeScale.largestSize)
    }

    /// The one question before a clip is gone, asked the same in a review and in Settings.
    func formClipDeleteConfirmation(isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) -> some View {
        destructiveConfirmation(
            "Delete this clip?",
            message: "It's only on this phone, so it can't come back. Your Set Log stays.",
            isPresented: isPresented,
            action: DestructiveAction(label: "Delete Clip", systemImage: "trash", identifier: "form-clip-delete-confirm"),
            onConfirm: onConfirm
        )
    }
}

/// What a share sends: the movie under a readable name, and its facts as the caption.
struct FormClipShare: Identifiable {
    let file: URL
    let caption: String
    var id: URL { file }
}

/// The full-screen review, on whichever clip of a Set the athlete is on. Reaches the clips itself,
/// so a Delete or a new Bar Path shows at once.
struct FormClipReviewView: View {
    let onClose: () -> Void
    /// Add Clip from inside the review. Nil where there is no Set card to return to, as in Settings.
    let onAdd: ((FormClip, FormClipSource) -> Void)?
    @Environment(FormClipLibrary.self) private var library
    @Environment(WorkoutStore.self) private var workout
    @State private var currentID: UUID

    init(clipID: UUID, onAdd: ((FormClip, FormClipSource) -> Void)?, onClose: @escaping () -> Void) {
        _currentID = State(initialValue: clipID)
        self.onAdd = onAdd
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if let clip = library.clip(currentID) {
                let siblings = library.clips(on: clip.setID, in: clip.spreadsheetId)
                FormClipReviewLoader(
                    clip: clip,
                    facts: clip.facts(in: workout.block),
                    movie: library.url(of: clip),
                    position: FormClipPosition(of: clip.id, in: siblings.map(\.id)),
                    onClose: onClose,
                    onNext: { currentID = $0 },
                    onAdd: onAdd.map { add in { source in add(clip, source) } }
                )
                .id(clip.id)
            }
        }
        .formClipRoom()
        .onAppear {
            // Ambient, so a review plays over the gym's music and stays silent on the silent switch.
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
        }
    }
}

/// Holds one clip's player for as long as that clip is on screen. A view's init runs on every
/// redraw, so the player is built here, once, as the screen appears.
private struct FormClipReviewLoader: View {
    let clip: FormClip
    let facts: FormClipFacts
    let movie: URL
    let position: FormClipPosition?
    let onClose: () -> Void
    let onNext: (UUID) -> Void
    let onAdd: ((FormClipSource) -> Void)?
    @Environment(\.themePalette) private var palette
    @State private var player: ClipPlayer?

    var body: some View {
        ZStack {
            palette.paperBackground.ignoresSafeArea()
            if let player {
                FormClipReviewScreen(
                    clip: clip,
                    facts: facts,
                    player: player,
                    position: position,
                    onClose: onClose,
                    onNext: onNext,
                    onAdd: onAdd
                )
            }
        }
        .onAppear {
            if player == nil { player = ClipPlayer(url: movie, duration: clip.duration) }
        }
    }
}

struct FormClipReviewScreen: View {
    let clip: FormClip
    let facts: FormClipFacts
    let player: ClipPlayer
    let position: FormClipPosition?
    let onClose: () -> Void
    let onNext: (UUID) -> Void
    let onAdd: ((FormClipSource) -> Void)?
    @Environment(FormClipLibrary.self) private var library
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = BarPathTraceStage.idle
    @State private var isPathShown = true
    @State private var failure: String?
    @State private var tracing: Task<Void, Never>?
    @State private var share: FormClipShare?
    @State private var isDeleteAsked = false
    @State private var isCompareOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topBar
            title
            FormClipSurface(
                player: player,
                path: clip.barPath,
                isPathShown: isPathShown,
                onTap: plateTap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(ClipPullToClose(isEnabled: stage == .idle, onClose: onClose))
            .accessibilityIdentifier("form-clip-surface")
            .layoutPriority(-1)

            status
            foot
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.bottom, 8)
        .background { palette.paperBackground.ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("form-clip-review")
        .accessibilityAction(.escape, onClose)
        .onAppear {
            player.setUp()
            if !reduceMotion, player.still == nil { player.play() }
        }
        .onDisappear {
            tracing?.cancel()
            player.tearDown()
        }
        .sheet(item: $share) { share in
            ShareSheet(items: [share.caption, share.file])
        }
        .fullScreenCover(isPresented: $isCompareOpen) {
            FormClipCompareView(clip: clip, onAdd: onAdd) { isCompareOpen = false }
        }
        .onChange(of: isCompareOpen) { _, isOpen in
            if isOpen { player.pause() }
        }
        .formClipDeleteConfirmation(isPresented: $isDeleteAsked, onConfirm: delete)
    }

    private var plateTap: ((CGPoint) -> Void)? {
        guard stage == .awaitingTap else { return nil }
        return { follow(from: $0) }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            ClipGlyphToggle(glyph: "xmark", label: "Close", id: "form-clip-close", isOn: false, onTap: onClose)
                .padding(.leading, -12)

            if let position {
                Button {
                    onNext(position.next)
                } label: {
                    Text(position.label)
                        .footPill(palette)
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel("Next clip of this Set")
                .accessibilityValue(position.label)
                .accessibilityIdentifier("form-clip-next")
            }

            Spacer(minLength: 8)

            ClipGlyphToggle(glyph: "square.and.arrow.up", label: "Share", id: "form-clip-share", isOn: false, onTap: shareClip)
            moreMenu
                .padding(.trailing, -12)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(facts.exerciseName)
                .themeFont(.sheetTitle)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("form-clip-title")
            Text(facts.line)
                .themeFont(.runline)
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(Theme.TypeRole.runline.denseFloorScale)
                .accessibilityIdentifier("form-clip-facts")
        }
    }

    private var moreMenu: some View {
        Menu {
            if let onAdd {
                if FormClipCamera.isAvailable {
                    Button("Record Clip") { onAdd(.camera) }
                }
                Button("Add Clip") { onAdd(.photos) }
            }
            if clip.barPath != nil {
                Button("Retrace Bar Path") { awaitTap() }
            }
            Button("Delete Clip", role: .destructive) { isDeleteAsked = true }
        } label: {
            Image(systemName: "ellipsis")
                .imageScale(.large)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("form-clip-more")
    }

    /// Room kept open under the movie, so nothing moves when the Bar Path has something to say.
    private var status: some View {
        let line = BarPathStatusLine.text(
            stage: stage,
            path: clip.barPath,
            isShown: isPathShown,
            failure: player.isUnplayable ? "This movie can't be played on this phone." : failure
        )
        return Text(line ?? " ")
            .themeFont(.runlineSecondary)
            .monospacedDigit()
            .foregroundStyle(stage == .awaitingTap ? palette.textPrimary : palette.textSecondary)
            .lineLimit(2, reservesSpace: true)
            .minimumScaleFactor(Theme.TypeRole.runlineSecondary.denseFloorScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("form-clip-status")
            .accessibilityHidden(line == nil)
    }

    private var foot: some View {
        VStack(spacing: 8) {
            ClipTimeReader(player: player)

            ClipPlayRow(isPlaying: player.isPlaying, onToggle: player.togglePlaying, onStep: player.step(by:))

            HStack(spacing: 0) {
                ClipRateRail(rate: player.rate, onSelect: player.setRate)
                Spacer(minLength: 4)
                ClipGlyphToggle(glyph: "repeat", label: "Loop", id: "form-clip-loop", isOn: player.loops) {
                    player.loops.toggle()
                }
                ClipGlyphToggle(
                    glyph: "point.topleft.down.to.point.bottomright.curvepath",
                    label: "Bar Path",
                    id: "form-clip-bar-path",
                    isOn: stage != .idle || (clip.barPath != nil && isPathShown),
                    onTap: barPathControlTapped
                )
                ClipGlyphToggle(glyph: "rectangle.split.2x1", label: "Compare", id: "form-clip-compare", isOn: false) {
                    isCompareOpen = true
                }
                .padding(.trailing, -9)
            }
        }
    }

    private func barPathControlTapped() {
        switch stage {
        case .idle:
            if clip.barPath == nil { awaitTap() } else { isPathShown.toggle() }
        case .awaitingTap:
            stage = .idle
        case .following:
            tracing?.cancel()
            stage = .idle
        }
    }

    private func awaitTap() {
        failure = nil
        player.pause()
        stage = .awaitingTap
    }

    /// Follows the plate from the tapped point on the frame on screen. The tracker's progress lands
    /// here a report at a time, off whichever thread read the frame.
    private func follow(from point: CGPoint) {
        HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
        let start = BarPathStart(time: player.time, x: point.x, y: point.y)
        stage = .following(share: 0)
        tracing = Task {
            do {
                try await library.traceBarPath(on: clip.id, from: start) { share in
                    Task { @MainActor in
                        if case .following = stage { stage = .following(share: share) }
                    }
                }
                isPathShown = true
            } catch is CancellationError {
            } catch {
                failure = (error as? BarPathTraceError)?.failureMessage ?? "The path couldn't be drawn. Try it again."
            }
            stage = .idle
        }
    }

    private func shareClip() {
        player.pause()
        do {
            share = FormClipShare(file: try library.shareableFile(of: clip, facts: facts), caption: facts.caption)
        } catch {
            failure = "This clip couldn't be readied to share. Try it again."
        }
    }

    private func delete() {
        do {
            try library.delete(clip.id)
            if let next = position?.next { onNext(next) } else { onClose() }
        } catch {
            failure = "This clip couldn't be deleted. Try it again."
        }
    }
}

/// The scrubber alone reads the playhead, so a frame's tick redraws it and nothing around it.
private struct ClipTimeReader: View {
    let player: ClipPlayer

    var body: some View {
        ClipScrubber(
            time: player.time,
            range: 0...player.duration,
            onBegan: player.beginScrub,
            onChanged: player.scrub(to:),
            onEnded: player.endScrub
        )
    }
}
