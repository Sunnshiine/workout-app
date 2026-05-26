import GoogleSignInSwift
import SwiftUI

struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var urlText = ""
    @State private var urlError = false
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer {
            if settings.isSignedIn {
                urlEntryCard
            } else {
                signInCard
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Phase 1: Sign-In Card

    private var signInCard: some View {
        VStack(spacing: 20) {
            Text("Connect your training sheet")
                .font(.title2.bold())

            GoogleSignInButton {
                Task {
                    guard let vc = topViewController() else { return }
                    do {
                        try await GoogleAuth.signIn(presenting: vc)
                        withAnimation { settings.isSignedIn = true }
                    } catch { settings.isSignedIn = false }
                }
            }
            .frame(maxWidth: 280)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .glassEffectID("onboarding", in: ns)
    }

    // MARK: - Phase 2: URL Entry Card

    private var urlEntryCard: some View {
        VStack(spacing: 20) {
            Text("Paste your sheet URL")
                .font(.title2.bold())

            TextField("Google Sheet URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if urlError {
                Text("That doesn't look like a Sheet URL")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Save") { urlError = !settings.setSheetURL(urlText) }
                .buttonStyle(.glass)
                .disabled(urlText.isEmpty)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .glassEffectID("onboarding", in: ns)
    }
}

@MainActor
func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}
