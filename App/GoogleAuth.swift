import Foundation
import GoogleSignIn

@MainActor
enum GoogleAuth {
    static let scope = [
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/drive.metadata.readonly"
    ]

    static func restorePreviousSignIn() async -> Bool {
        await withCheckedContinuation { cont in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                guard let user else {
                    cont.resume(returning: false)
                    return
                }

                guard hasRequiredScopes(user.grantedScopes) else {
                    GIDSignIn.sharedInstance.signOut()
                    cont.resume(returning: false)
                    return
                }

                cont.resume(returning: true)
            }
        }
    }

    static func signIn(presenting vc: UIViewController) async throws {
        try await GIDSignIn.sharedInstance.signIn(withPresenting: vc, hint: nil, additionalScopes: scope)
    }

    static func signOut() { GIDSignIn.sharedInstance.signOut() }

    static func hasRequiredScopes(_ grantedScopes: [String]?) -> Bool {
        guard let grantedScopes else { return false }
        return Set(scope).isSubset(of: Set(grantedScopes))
    }

    /// A fresh access token, refreshing if needed.
    static func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw SheetsError.notAuthorized }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }
}
