import GoogleSignInSwift
import SwiftUI

struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var urlText = ""
    @State private var urlError = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Connect your training sheet").font(.title2.bold())

            GoogleSignInButton {
                Task {
                    guard let vc = topViewController() else { return }
                    do {
                        try await GoogleAuth.signIn(presenting: vc)
                        settings.isSignedIn = true
                    } catch { settings.isSignedIn = false }
                }
            }
            .frame(maxWidth: 280)
            .opacity(settings.isSignedIn ? 0.4 : 1)

            if settings.isSignedIn {
                TextField("Paste your Google Sheet URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if urlError { Text("That doesn't look like a Sheet URL").font(.caption).foregroundStyle(.red) }
                Button("Save") { urlError = !settings.setSheetURL(urlText) }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlText.isEmpty)
            }
        }
        .padding()
    }
}

@MainActor
func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}
