import SwiftUI
import UIKit

/// The full Session queue in a medium sheet: every stage item in Session order
/// with its Set dots, the one on stage marked "Now", and Move On in the footer
/// when the Session can advance. Tapping an incomplete row brings it on stage.
///
/// Superset pairing also lives here: `Pair` on an eligible row starts pairing,
/// the row taps pick the partner, `Unlink` on a Superset's group dissolves it,
/// and the sheet falls back to browsing when pairing ends or the sheet closes.
struct SessionQueueSheet: View {
    let queue: SessionQueue
    let session: Session
    let coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    private var isPairing: Bool {
        queue.isPairing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(queue.rows) { row in
                    queueRow(for: row)
                }

                if !isPairing, !queue.openExercises.isEmpty {
                    OpenExercisesSection(exercises: queue.openExercises) { exercise in
                        dismiss()
                        coordinator.showSourceSession(of: exercise)
                    }
                    .padding(.top, Theme.cardSpacing)
                }

                if queue.showsMoveOn, !isPairing {
                    SessionMoveOnButton(accessibilityID: "queue-move-on-button") {
                        dismiss()
                        coordinator.moveOn()
                    }
                    .padding(.top, Theme.cardSpacing)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaBar(edge: .top) {
            header
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.18), value: queue.pairingMode)
        .animation(.easeInOut(duration: 0.18), value: queue.rows.map(\.id))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.soft)
        .presentationBackground { palette.paperBackground }
        .onDisappear(perform: coordinator.cancelPairing)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isPairing ? "Pick a partner" : "This Session")
                .font(Theme.font(.sheetTitle))
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 12)

            textButton("Cancel", color: palette.accent, action: coordinator.cancelPairing)
                .accessibilityIdentifier("stage-queue-cancel-pairing")
                .shown(isPairing)
        }
        .padding(.top, 18)
    }

    // MARK: - Rows

    @ViewBuilder
    private func queueRow(for row: SessionQueue.Row) -> some View {
        switch row.kind {
        case .exercise:
            rowButton(for: row)
        case .pairableExercise:
            HStack(spacing: 0) {
                rowButton(for: row)
                if !isPairing {
                    textButton("Pair", color: palette.textSecondary) {
                        coordinator.beginPairing(from: row.pairingExercise, in: session)
                    }
                    .accessibilityLabel("Pair \(row.title) into a superset")
                    .accessibilityIdentifier("stage-queue-pair-\(row.id)")
                }
            }
        case .superset:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Superset")
                        .font(Theme.font(.fieldLabel))
                        .foregroundStyle(palette.textSecondary)

                    Spacer(minLength: 12)

                    textButton("Unlink", color: palette.textSecondary) {
                        coordinator.dismissSuperset(containing: row.pairingExercise, in: session)
                    }
                    .accessibilityLabel("Unlink \(row.title)")
                    .accessibilityIdentifier("stage-queue-unlink-\(row.id)")
                    .shown(!isPairing)
                }
                .padding(.leading, 14)

                rowButton(for: row)
            }
            .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
        }
    }

    @ViewBuilder
    private func rowButton(for row: SessionQueue.Row) -> some View {
        if isPairing {
            pairingRow(for: row)
        } else {
            jumpButton(for: row)
        }
    }

    // MARK: - Browsing

    private func jumpButton(for row: SessionQueue.Row) -> some View {
        Button {
            dismiss()
            if let target = row.jumpTarget {
                coordinator.focus(on: target)
            }
        } label: {
            rowLabel(for: row) {
                if row.isOnStage {
                    accentWord("Now")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(row.isComplete)
        .accessibilityIdentifier("stage-queue-row-\(row.id)")
    }

    private func textButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(.queuePill))
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pairing

    private func pairingRow(for row: SessionQueue.Row) -> some View {
        Button {
            if coordinator.handlePairingTap(on: row.pairingExercise, in: session) == .unavailable {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        } label: {
            rowLabel(for: row) {
                pairingIndicator(for: row.pairingRole)
            }
        }
        .buttonStyle(.plain)
        .opacity(row.pairingRole == .ineligibleTarget ? Theme.pairingUnavailableOpacity : 1)
        .overlay {
            if row.pairingRole == .confirmingTarget {
                RoundedRectangle(cornerRadius: Theme.Radius.soft)
                    .stroke(palette.accent, lineWidth: 2)
            }
        }
        .accessibilityIdentifier("stage-queue-row-\(row.id)")
    }

    @ViewBuilder
    private func pairingIndicator(for role: QueuePairingRole) -> some View {
        switch role {
        case .source:
            accentWord("Pairing")
        case .eligibleTarget, .confirmingTarget:
            accentWord("Pair with this")
        case .none, .ineligibleTarget:
            EmptyView()
        }
    }

    // MARK: - Row label

    private func accentWord(_ word: String) -> some View {
        Text(word)
            .font(Theme.font(.fieldLabel))
            .foregroundStyle(palette.accent)
    }

    private func rowLabel(for row: SessionQueue.Row, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(row.isComplete ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(1)

                SessionStageSetDots(sets: row.sets)
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

extension View {
    /// Hides a control without giving up its frame, so the rows around it hold still.
    fileprivate func shown(_ isShown: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .disabled(!isShown)
            .accessibilityHidden(!isShown)
    }
}
