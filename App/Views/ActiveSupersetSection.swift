import SwiftUI

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
            cardIdentity: stage.card?.cardIdentity,
            lastPerformed: stage.lastPerformed.map { presentation in
                LastPerformedCard(presentation: presentation) {
                    onShowHistory(stage.focused)
                }
            }
        ) {
            nameBlock
        } branch: {
            SessionStageBranch(fork: stage.branch)
        } card: {
            if let slot = stage.card {
                ActiveSetCard(slot: slot, coordinator: coordinator)
                    .holdsStill(acrossChangesOf: slot.cardIdentity)
            }
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            StageExerciseName(name: stage.focused.exerciseName.base)

            Button {
                coordinator.focusNextSupersetSet(for: stage.partner, in: session)
            } label: {
                Text("\(Image(systemName: "arrow.triangle.branch"))\(Text("\u{00A0}").tracking(2))\(stage.partner.exerciseName.base)")
                    .imageScale(.small)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .themeFont(.supersetPartner)
                    .foregroundStyle(palette.supersetPartnerName)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("& \(stage.partner.exerciseName.base)")
            .accessibilityHint("Switches focus to \(stage.partner.exerciseName.base)")
            .accessibilityIdentifier("superset-partner-name")
        }
    }
}
