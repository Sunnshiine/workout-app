import SwiftUI

struct SessionProgressHeader: View {
    let session: Session

    private var presentation: SessionProgressHeaderPresentation {
        SessionProgressHeaderPresentation(session: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(presentation.breadcrumb)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(presentation.remainingText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            ProgressView(value: presentation.progress)
                .tint(Theme.accent)
                .accessibilityLabel("Session progress")
                .accessibilityValue("\(presentation.completedSetCount) of \(presentation.totalSetCount) sets")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
