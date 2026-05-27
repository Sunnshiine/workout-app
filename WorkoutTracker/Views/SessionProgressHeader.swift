import SwiftUI

struct SessionProgressHeader: View {
    let session: Session

    private var presentation: SessionProgressHeaderPresentation {
        SessionProgressHeaderPresentation(session: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(presentation.breadcrumb)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(presentation.remainingText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.progressTrack, in: .capsule)
            }

            GeometryReader { geometry in
                let progress = min(max(presentation.progress, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.progressTrack)

                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geometry.size.width * CGFloat(progress))
                }
            }
            .frame(height: 5)
            .accessibilityLabel("Session progress")
            .accessibilityValue("\(presentation.completedSetCount) of \(presentation.totalSetCount) sets")
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}
