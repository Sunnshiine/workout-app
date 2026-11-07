import SwiftUI

struct DestructiveAction {
    let label: String
    let systemImage: String
    let identifier: String
}

/// An `.alert` action drops its Label's glyph on iOS 26 and draws the text alone, so the
/// confirmations of what can't be undone draw their own alert to show the icon. Like a system
/// alert, the card holds the presentation under it until the athlete answers.
private struct DestructiveConfirmation: ViewModifier {
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isTitleFocused: Bool
    let title: String
    let message: String
    @Binding var isPresented: Bool
    let action: DestructiveAction
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        // The blur keeps the rows that outrun the card from reading as a second card behind it. It also
        // fades the page at its edges, so the same paper sits under it and no rim shows.
        content
            .blur(radius: isPresented ? 6 : 0)
            .background(palette.paperBackground.ignoresSafeArea())
            .overlay {
                ZStack {
                    if isPresented {
                        Color.black.opacity(0.35).ignoresSafeArea()
                            .transition(.opacity)
                        // The card turns opaque ahead of its scale, so the rows behind never read through its words.
                        // It leaves ahead of the blur, so its words never hang over rows already sharp.
                        card
                            .transition(
                                .asymmetric(
                                    insertion: reduceMotion
                                        ? .opacity
                                        : .scale(scale: 0.96).combined(with: .opacity.animation(.easeOut(duration: 0.1))),
                                    removal: .opacity.animation(.easeOut(duration: 0.06))
                                )
                            )
                            // A removed view can draw under its sibling, so only a zIndex keeps the card above the scrim.
                            .zIndex(1)
                    }
                }
            }
            // The answer is already given, so the card leaves faster than it came.
            .animation(isPresented ? .easeOut(duration: 0.2) : .easeOut(duration: 0.1).delay(0.05), value: isPresented)
            .interactiveDismissDisabled(isPresented)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
                .accessibilityFocused($isTitleFocused)
            Text(message)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 12) {
                Button(role: .cancel) {
                    isPresented = false
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button(role: .destructive) {
                    onConfirm()
                    isPresented = false
                } label: {
                    Label(action.label, systemImage: action.systemImage)
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // System red as the fill, so the glyph holds the mark floor with no retint.
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(action.identifier)
            }
            .fixedSize(horizontal: false, vertical: true)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 12)
        }
        .padding(24)
        .background(palette.sheetFill, in: .rect(cornerRadius: Theme.Radius.soft))
        .themeElevation(palette.surfaceShadow, in: .rect(cornerRadius: Theme.Radius.soft))
        .padding(.horizontal, Theme.pageMargin)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(title)
        .accessibilityAction(.escape) { isPresented = false }
        .task { isTitleFocused = true }
    }
}

extension View {
    func destructiveConfirmation(
        _ title: String,
        message: String,
        isPresented: Binding<Bool>,
        action: DestructiveAction,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            DestructiveConfirmation(title: title, message: message, isPresented: isPresented, action: action, onConfirm: onConfirm)
        )
    }
}
