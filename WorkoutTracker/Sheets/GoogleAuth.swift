import Foundation
import GoogleSignIn

@MainActor
enum GoogleAuth {
    static let scope = "https://www.googleapis.com/auth/spreadsheets"

    static func restorePreviousSignIn() async -> Bool {
        await withCheckedContinuation { cont in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in cont.resume(returning: user != nil) }
        }
    }

    static func signIn(presenting vc: UIViewController) async throws {
        try await GIDSignIn.sharedInstance.signIn(withPresenting: vc, hint: nil, additionalScopes: [scope])
    }

    static func signOut() { GIDSignIn.sharedInstance.signOut() }

    /// A fresh access token, refreshing if needed.
    static func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw SheetsError.notAuthorized }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }
}
