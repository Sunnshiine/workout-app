import Testing

@testable import WorkoutTracker

@MainActor
@Test func googleAuthRequiresSheetsAndDriveMetadataScopes() {
    let sheetsScope = "https://www.googleapis.com/auth/spreadsheets"
    let driveScope = "https://www.googleapis.com/auth/drive.metadata.readonly"

    #expect(Set(GoogleAuth.scope) == Set([sheetsScope, driveScope]))
    #expect(GoogleAuth.hasRequiredScopes([sheetsScope, driveScope]))
    #expect(!GoogleAuth.hasRequiredScopes([sheetsScope]))
    #expect(!GoogleAuth.hasRequiredScopes(nil))
}
