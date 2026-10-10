import SwiftUI
import UIKit

/// The full Session queue in a medium sheet: every stage item in Session order
/// with its Set dots, the one on stage marked "Now", and Move On in the footer
/// when the Session can advance. Tapping an incomplete row brings it on stage.
///
/// Superset pairing also lives here: the link affordance on an eligible row
/// starts pairing, the row taps pick the partner, and the sheet falls back to
/// browsing when pairing ends or the sheet closes.
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
                header

                ForEach(queue.rows) { row in
                    if isPairing {
                        pairingRow(for: row)
                    } else {
                        queueRow(for: row)
                    }
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
        .animation(.easeInOut(duration: 0.18), value: queue.pairingMode)
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

            if isPairing {
                Button("Cancel", action: coordinator.cancelPairing)
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("stage-queue-cancel-pairing")
            }
        }
        .padding(.top, 18)
    }

    // MARK: - Browsing

    private func queueRow(for row: SessionQueue.Row) -> some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
                if let target = row.jumpTarget {
                    coordinator.focus(on: target)
                }
            } label: {
                rowLabel(for: row) {
                    if row.isOnStage {
                        Text("Now")
                            .font(Theme.font(.fieldLabel))
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(row.isComplete)
            .accessibilityIdentifier("stage-queue-row-\(row.id)")

            if row.canBeginPairing {
                Button {
                    coordinator.beginPairing(from: row.pairingExercise, in: session)
                } label: {
                    Image(systemName: "link")
                        .font(Theme.font(.queuePill))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pair \(row.title) into a superset")
                .accessibilityIdentifier("stage-queue-pair-\(row.id)")
            }
        }
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
            Image(systemName: "link")
                .font(Theme.font(.fieldLabel))
                .foregroundStyle(palette.accent)
        case .confirmingTarget:
            Image(systemName: "link.badge.plus")
                .font(Theme.font(.fieldLabel))
                .foregroundStyle(palette.accent)
        case .none, .eligibleTarget, .ineligibleTarget:
            EmptyView()
        }
    }

    // MARK: - Row label

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
