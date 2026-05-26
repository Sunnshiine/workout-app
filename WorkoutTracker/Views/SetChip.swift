import SwiftUI

struct SetChip: View {
    let reps: String
    let load: String

    var body: some View {
        HStack(spacing: 6) {
            Text(reps)
            Text(load)
                .foregroundStyle(Theme.accent)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.14), in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
    }
}
