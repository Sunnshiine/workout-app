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
    @State private var isScrolled = false

    private var isPairing: Bool {
        queue.isPairing
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)

            rows
        }
        .animation(.easeInOut(duration: 0.18), value: queue.pairingMode)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.soft)
        .presentationBackground { palette.paperBackground }
        .onDisappear(perform: coordinator.cancelPairing)
    }

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
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
        .safeAreaPadding(.top, 8)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0 } action: {
            isScrolled = $1
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [isScrolled ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                Color.black
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isPairing ? "Pick a partner" : "This Session")
                .font(Theme.font(.sheetTitle))
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 12)

            Button(action: coordinator.cancelPairing) {
                Text("Cancel")
                    .font(Theme.font(.queuePill))
                    .foregroundStyle(palette.actionInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stage-queue-cancel-pairing")
            .visibleKeepingFrame(isPairing)
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
                            .foregroundStyle(palette.actionInk)
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
                        .frame(minWidth: 44)
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
        .accessibilityValue(row.pairingRole == .ineligibleTarget ? "Unavailable" : "")
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
                .foregroundStyle(palette.actionInk)
                .accessibilityLabel("Pairing")
        case .confirmingTarget:
            Image(systemName: "link.badge.plus")
                .font(Theme.font(.fieldLabel))
                .foregroundStyle(palette.actionInk)
                .accessibilityLabel("Pairing with this")
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

extension View {
    fileprivate func visibleKeepingFrame(_ isShown: Bool) -> some View {
        hidden().overlay {
            if isShown {
                self
            }
        }
    }
}
