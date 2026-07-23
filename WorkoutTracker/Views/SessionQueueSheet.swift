import SwiftUI

/// The full Session queue in a medium sheet: every stage item in Session order
/// with its Set dots, the one on stage marked "Now", and Move On in the footer
/// when the Session can advance. Tapping an incomplete row brings it on stage.
///
/// Superset pairing also lives here: the link affordance on an eligible row
/// starts pairing, the row taps pick the partner, and the sheet falls back to
/// browsing when pairing ends or the sheet closes.
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

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
        // Living paper (DESIGN.md §2, ledger §10.1): the queue sheet carries the washes on soft
        // shoulders — bare cream reads too white — so it stays in the same room as the stage.
        .presentationCornerRadius(Theme.Radius.soft)
        .presentationBackground { palette.paperBackground }
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
                    // Rows shed their icons (ledger §10.2): the stage's icon budget is spent on the
                    // branch. A completed row reads as complete from its dimmed title and settled Set
                    // dots alone; only the on-stage row still speaks, in words.
                    if isOnStage {
                        Text("Now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(item.isComplete)
            .accessibilityIdentifier("stage-queue-row-\(item.id)")

            if canBeginPairing(item) {
                Button {
                    onBeginPairing(item)
                } label: {
                    Image(systemName: "link")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pair \(item.title) into a superset")
                .accessibilityIdentifier("stage-queue-pair-\(item.id)")
            }
        }
    }

    // MARK: - Pairing

    private func pairingRow(for item: SessionStageItem, role: QueuePairingRole) -> some View {
        Button {
            onPairingTap(item)
        } label: {
            rowLabel(for: item) {
                pairingIndicator(for: role)
            }
        }
        .buttonStyle(.plain)
        .opacity(role == .ineligibleTarget ? Theme.pairingUnavailableOpacity : 1)
        .overlay {
            if role == .confirmingTarget {
                // The confirming-pair ring loses its accent glow and retired radius-16 (ledger §10.2):
                // one clean soft-radius stroke, no second glow to break the One Glow Rule at night.
                RoundedRectangle(cornerRadius: Theme.Radius.soft)
                    .stroke(palette.accent, lineWidth: 2)
            }
        }
        .accessibilityIdentifier("stage-queue-row-\(item.id)")
    }

    @ViewBuilder
    private func pairingIndicator(for role: QueuePairingRole) -> some View {
        switch role {
        case .source:
            Image(systemName: "link")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.accent)
        case .confirmingTarget:
            Image(systemName: "link.badge.plus")
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.accent)
        case .none, .eligibleTarget, .ineligibleTarget:
            EmptyView()
        }
    }

    // MARK: - Row label

    private func rowLabel(for item: SessionStageItem, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isComplete ? .secondary : .primary)
                    .lineLimit(1)

                SessionStageSetDots(sets: item.sortedSets)
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
