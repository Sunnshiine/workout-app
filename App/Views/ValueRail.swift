import SwiftUI
import Synchronization

// MARK: - Value rail (Reps / RPE)

/// The Reps or RPE rail. Under VoiceOver it reads as one adjustable element; otherwise its cells
/// stay buttons, for Voice Control, the Large Content Viewer, and the tests that tap them.
struct ValueRail: View {
    let chips: [ValueRailChip]
    let selectedIndex: Int
    let label: String
    var isInvalid = false
    let onSelect: (String) -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRuns

    var body: some View {
        ValueRailControl(
            chips: chips,
            selectedIndex: selectedIndex,
            label: label,
            isInvalid: isInvalid,
            readsAsOneElement: voiceOverRuns,
            onSelect: onSelect
        )
    }
}

/// The rail with its accessibility shape decided, so a hosted test can read it as VoiceOver does.
struct ValueRailControl: View {
    let chips: [ValueRailChip]
    let selectedIndex: Int
    let label: String
    let isInvalid: Bool
    let readsAsOneElement: Bool
    let onSelect: (String) -> Void
    /// A drag is in flight, or ended this event turn. It gates the cell buttons: the lifted finger
    /// sits over a cell other than the one the drag chose, and that cell's button firing on release
    /// would override the drag. The flag clears one runloop turn after the drag ends, after the
    /// synchronous release has been suppressed.
    @State private var isDragging = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        if readsAsOneElement {
            rail
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(chips.spokenSelection)
                .accessibilityAdjustableAction { direction in
                    select(index: selectedIndex + (direction == .increment ? 1 : -1))
                }
                .accessibilityIdentifier("\(label.lowercased())-rail")
        } else {
            rail
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
        }
    }

    private var rail: some View {
        VStack(spacing: 8) {
            RailTrack(
                count: chips.count,
                selectedIndex: selectedIndex,
                isInvalid: isInvalid,
                onDragStart: { isDragging = true },
                onDragEnd: { DispatchQueue.main.async { isDragging = false } },
                onCommit: select(index:),
                strip: {
                    HStack(spacing: 0) {
                        ForEach(chips) { chip in
                            cell(chip)
                        }
                    }
                }
            )

            Text(label)
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func select(index: Int) {
        guard chips.indices.contains(index) else { return }
        onSelect(chips[index].label)
        HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
    }

    private func cell(_ chip: ValueRailChip) -> some View {
        Button {
            guard !isDragging else { return }
            onSelect(chip.label)
            HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
        } label: {
            Text(chip.label)
                .themeFont(.railChipValue)
                .foregroundStyle(chip.isSelected ? palette.textPrimary : palette.textSecondary)
                .frame(width: Theme.railCellWidth, height: Theme.railCellHeight)
                .contentShape(.rect)
                .background {
                    if chip.isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.cell)
                            .fill(palette.railSelectedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.cell)
                                    .strokeBorder(palette.action, lineWidth: 2)
                            )
                            .padding(Theme.railCellInset)
                    }
                }
                .overlay(alignment: .bottom) {
                    if chip.isPrescribed {
                        Capsule()
                            .fill(palette.prescriptionTick)
                            .frame(width: Theme.prescriptionTickWidth, height: Theme.prescriptionTickHeight)
                            .padding(.bottom, Theme.railCellInset + 3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer {
            Text("\(label) \(chip.label)")
        }
        .accessibilityIdentifier(chip.accessibilityIdentifier)
        .accessibilityLabel("\(label) \(chip.label)")
        .accessibilityAddTraits(chip.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The track and the strip of cells sliding in it. The finger's state lives here, below the cells,
/// so a drag redraws the strip's offset each frame and nothing else.
private struct RailTrack<Strip: View>: View {
    let count: Int
    let selectedIndex: Int
    let isInvalid: Bool
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onCommit: (Int) -> Void
    @ViewBuilder let strip: Strip
    @State private var drag: RailDrag?
    @State private var yieldsToVertical = false
    @State private var drawn = DrawnOffset()
    @GestureState private var isTouching = false
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        GeometryReader { geo in
            let layout = ValueRailLayout(trackWidth: geo.size.width, cellWidth: Theme.railCellWidth, spacing: 0, count: count)
            let offset =
                drag.map { layout.draggedOffset(anchor: $0.anchor, translation: $0.translation) }
                ?? layout.offset(centering: selectedIndex)

            strip
                .frame(height: geo.size.height)
                .transaction(slideTransaction) { content in
                    content
                        .background { Color.clear.modifier(DrawnOffsetProbe(x: offset, drawn: drawn)) }
                        .offset(x: offset)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .contentShape(.rect)
                .simultaneousGesture(slide(in: layout))
        }
        .frame(height: Theme.railTrackHeight)
        .mask { edgeFadeMask }
        .background(palette.railFill, in: .rect(cornerRadius: Theme.Radius.rail))
        .clipShape(.rect(cornerRadius: Theme.Radius.rail))
        .contentShape(.rect(cornerRadius: Theme.Radius.rail))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.rail)
                .strokeBorder(isInvalid ? palette.danger : .clear, lineWidth: 2)
        }
        // A gesture the system cancels never reaches `onEnded`, and one that yielded has nothing to
        // release; the gesture state's reset ends both.
        .onChange(of: isTouching) { _, touching in
            guard !touching else { return }
            if let drag {
                release(drag, velocity: 0)
            } else if yieldsToVertical {
                onDragEnd()
            }
            yieldsToVertical = false
        }
    }

    /// The slide's own transaction, scoped to the offset and its probe so the cells keep the ambient
    /// one: no animation while the finger is down, and a tap's recentre on the settle spring.
    private func slideTransaction(_ transaction: inout Transaction) {
        if drag != nil || transaction.disablesAnimations {
            transaction.animation = nil
        } else if transaction.animation == nil {
            transaction.animation = ValueRailLayout.settle(reducesMotion: reducesMotion).animation(initialVelocity: 0)
        }
    }

    /// Past the hysteresis the first move is a drag on either axis, so the cell under the finger
    /// does not fire on release; then it decides the axis. A horizontal drag takes the strip from
    /// where it is drawn, so a grab mid-settle starts there, and commits each detent that crosses
    /// the centre. A vertical one is left to the surface beneath.
    private func slide(in layout: ValueRailLayout) -> some Gesture {
        DragGesture(minimumDistance: Theme.Gesture.hysteresis)
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { value in
                let translation = value.translation.width
                if drag == nil {
                    guard !yieldsToVertical else { return }
                    onDragStart()
                    guard ValueRailLayout.claimsAxis(value.translation) else {
                        yieldsToVertical = true
                        return
                    }
                    let anchor = layout.dragAnchor(grabbedAt: drawn.value.withLock { $0 }, translation: translation)
                    drag = RailDrag(layout: layout, anchor: anchor, translation: translation, committedIndex: selectedIndex)
                }
                guard var moved = drag else { return }
                moved.translation = translation
                let centred = layout.centredIndex(at: layout.draggedOffset(anchor: moved.anchor, translation: translation))
                if centred != moved.committedIndex {
                    moved.committedIndex = centred
                    onCommit(centred)
                }
                drag = moved
            }
            .onEnded { value in
                guard let drag else { return }
                release(drag, velocity: value.velocity.width)
            }
    }

    /// The landing's value is written outside the animation, so the cell fill and the Log capsule
    /// change in the next frame (§5.2) and only the strip's slide rides the spring.
    private func release(_ drag: RailDrag, velocity: CGFloat) {
        let offset = drag.layout.draggedOffset(anchor: drag.anchor, translation: drag.translation)
        let landing = drag.layout.landing(liftedAt: offset, velocity: velocity, reducesMotion: reducesMotion)
        if landing.index != drag.committedIndex { onCommit(landing.index) }
        withAnimation(landing.spring.animation(initialVelocity: landing.initialVelocity)) {
            self.drag = nil
        }
        onDragEnd()
    }

    /// Fades the chips out at both ends without painting over the rail's rounded fill.
    private var edgeFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Theme.railEdgeFadeWidth)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Theme.railEdgeFadeWidth)
        }
    }
}

private struct RailDrag {
    let layout: ValueRailLayout
    let anchor: CGFloat
    var translation: CGFloat
    var committedIndex: Int
}

/// The strip's offset as last drawn, written from inside the animation so a finger that lands
/// mid-settle grabs the strip where it is, not where it was going.
private final class DrawnOffset: Sendable {
    let value = Mutex<CGFloat>(0)
}

/// Rides the same animation as the `.offset` beside it and records each frame's value. It sits on
/// a clear background rather than on the strip: a geometry effect around text resamples the glyphs
/// at a sub-pixel position, where `.offset` alone keeps them on the pixel grid.
private struct DrawnOffsetProbe: GeometryEffect {
    var x: CGFloat
    let drawn: DrawnOffset

    var animatableData: CGFloat {
        get { x }
        set { x = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        drawn.value.withLock { $0 = x }
        return ProjectionTransform()
    }
}
