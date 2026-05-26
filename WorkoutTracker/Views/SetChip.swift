import SwiftUI

struct SetChip: View {
    let index: Int
    let reps: String
    let load: String

    var body: some View {
        HStack(spacing: 6) {
            Text("S\(index + 1)")
                .fontWeight(.medium)
                .foregroundStyle(Theme.accent)
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
