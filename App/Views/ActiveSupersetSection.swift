import SwiftUI

/// The Superset stage (DESIGN.md §5.4, picks superset-stage4-a/-b): the same
/// editorial column as a single Exercise — Cadence, the Fraunces name, the coach
/// note, the branch, Last Performed, and the Active Set Card — but the name gains
/// a subordinate "& partner" line and the branch becomes **one forked stem**. The
/// focused Exercise leads; the "& partner" line is the manual focus switch onto
/// the resting side. Superset mechanics (alternation, pairing, the queue sheet's
/// containment) are untouched — this slice rebuilds only the composition.
struct ActiveSupersetSection: View {
    let stage: SupersetStage
    let session: Session
    let coordinator: SessionCoordinator
    let composition: SessionStageComposition
    let onShowHistory: (Exercise) -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        SessionStageColumn(
            exercise: stage.focused,
            composition: composition,
            lastPerformed: stage.lastPerformed.map { presentation in
                LastPerformedCard(presentation: presentation) {
                    onShowHistory(stage.focused)
                }
            }
        ) {
            nameBlock
        } branch: {
            SessionStageBranch(branch: stage.branch, partnerNodes: stage.partnerNodes)
        } card: {
            if let slot = stage.card {
                ActiveSetCard(slot: slot, coordinator: coordinator)
                    .holdsStill(acrossChangesOf: slot.id)
            }
        }
    }

    // The focused Exercise's Fraunces name leads; below it the subordinate
    // "& partner" line (foliage green by Day, translucent foliage at Night) is the
    // manual focus switch onto the resting side (DESIGN.md §5.4).
    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stage.focused.baseName)
                .font(Theme.font(.exerciseName))
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("stage-exercise-name")

            Button {
                coordinator.focusNextSupersetSet(for: stage.partner, in: session)
            } label: {
                Text("& \(stage.partner.baseName)")
                    .font(Theme.font(.supersetPartner))
                    .foregroundStyle(palette.supersetPartnerBranch)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("& \(stage.partner.baseName)")
            .accessibilityHint("Switches focus to \(stage.partner.baseName)")
            .accessibilityIdentifier("superset-partner-name")
        }
    }
}
