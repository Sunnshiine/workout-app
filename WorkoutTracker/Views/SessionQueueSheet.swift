import SwiftUI

/// The full Session queue in a medium sheet: every stage item in Session order
/// with its branch, the one on stage marked "Now", and Move On in the footer
/// when the Session can advance. Tapping an incomplete row brings it on stage.
///
/// Superset pairing lives here with no new glyphs (DESIGN.md §5.4): a `Pair`
/// affordance on an eligible row starts pairing, `Pair with this` on a partner
/// confirms it, and a formed Superset reads by containment — one soft group with
/// a sentence-case `Superset` caption and an `Unlink` control.
struct SessionQueueSheet: View {
    let items: [SessionStageItem]
    let stageItemID: String?
    let showsMoveOn: Bool
    let openExercises: [Exercise]
    let pairingMode: PairingMode
    let canBeginPairing: (SessionStageItem) -> Bool
    let onJump: (SessionStageItem) -> Void
    let onMoveOn: () -> Void
    let onSelectOpenExercise: (Exercise) -> Void
    let onBeginPairing: (SessionStageItem) -> Void
    let onPairingTap: (SessionStageItem) -> Void
    let onCancelPairing: () -> Void
    let onUnlink: (SessionStageItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    private func isSuperset(_ item: SessionStageItem) -> Bool {
        if case .superset = item.item { return true }
        return false
    }

    private var isPairing: Bool {
        pairingMode != .inactive
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                ForEach(items) { item in
                    if isPairing {
                        pairingRow(
                            for: item,
                            role: SessionStagePresentation.pairingRole(of: item, mode: pairingMode)
                        )
                    } else if isSuperset(item) {
                        supersetGroup(for: item, isOnStage: item.id == stageItemID)
                    } else {
                        queueRow(for: item, isOnStage: item.id == stageItemID)
                    }
                }

                if !isPairing, !openExercises.isEmpty {
                    OpenExercisesSection(exercises: openExercises) { exercise in
                        dismiss()
                        onSelectOpenExercise(exercise)
                    }
                    .padding(.top, Theme.cardSpacing)
                }

                if showsMoveOn, !isPairing {
                    SessionMoveOnButton(accessibilityID: "queue-move-on-button") {
                        dismiss()
                        onMoveOn()
                    }
                    .padding(.top, Theme.cardSpacing)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .animation(.easeInOut(duration: 0.18), value: pairingMode)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onDisappear(perform: onCancelPairing)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isPairing ? "Pick a partner" : "This Session")
                .font(.headline)

            Spacer(minLength: 12)

            if isPairing {
                Button("Cancel", action: onCancelPairing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("stage-queue-cancel-pairing")
            }
        }
        .padding(.top, 18)
    }

    // MARK: - Browsing

    private func queueRow(for item: SessionStageItem, isOnStage: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
                onJump(item)
            } label: {
                rowLabel(for: item) {
                    if isOnStage {
                        Text("Now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    } else if item.isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(item.isComplete)
            .accessibilityIdentifier("stage-queue-row-\(item.id)")

            if canBeginPairing(item) {
                // Creation begins as a plain word — `Pair` → `Pair with this` — no bracket glyph.
                Button("Pair") {
                    onBeginPairing(item)
                }
                .font(Theme.font(.queuePill))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel("Pair \(item.title) into a superset")
                .accessibilityIdentifier("stage-queue-pair-\(item.id)")
            }
        }
    }

    // MARK: - Containment (a formed Superset)

    private func supersetGroup(for item: SessionStageItem, isOnStage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Superset")
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(.secondary)

                if isOnStage {
                    Text("Now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }

                Spacer(minLength: 12)

                Button("Unlink") {
                    onUnlink(item)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.accent)
                .buttonStyle(.plain)
                .accessibilityIdentifier("stage-queue-unlink-\(item.id)")
            }

            Button {
                dismiss()
                onJump(item)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(item.exercises, id: \.order) { exercise in
                        containedExerciseLine(exercise)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.isComplete)
            .accessibilityIdentifier("stage-queue-row-\(item.id)")
        }
        .padding(14)
        .background(palette.footFill, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(palette.queueStroke, lineWidth: 1)
        )
    }

    private func containedExerciseLine(_ exercise: Exercise) -> some View {
        let sortedSets = exercise.sets.sorted { $0.index < $1.index }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                SessionStageBranch(sets: sortedSets)
            }

            Spacer(minLength: 12)
        }
    }

    // MARK: - Pairing

    private func pairingRow(for item: SessionStageItem, role: QueuePairingRole) -> some View {
        HStack(spacing: 0) {
            rowLabel(for: item) {
                if role == .source {
                    Text("Pairing…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
            }

            if role == .eligibleTarget || role == .confirmingTarget {
                Button("Pair with this") {
                    onPairingTap(item)
                }
                .font(Theme.font(.queuePill))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityIdentifier("stage-queue-pairwith-\(item.id)")
            }
        }
        .opacity(role == .ineligibleTarget ? Theme.pairingUnavailableOpacity : 1)
        .overlay {
            if role == .confirmingTarget {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(palette.accent, lineWidth: 2)
                    .shadow(color: palette.accent.opacity(0.65), radius: 12)
            }
        }
        .accessibilityIdentifier("stage-queue-row-\(item.id)")
    }

    // MARK: - Row label

    private func rowLabel(for item: SessionStageItem, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isComplete ? .secondary : .primary)
                    .lineLimit(1)

                SessionStageBranch(sets: item.sortedSets)
            }

            Spacer(minLength: 12)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
