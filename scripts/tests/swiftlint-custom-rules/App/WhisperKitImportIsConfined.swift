enum WhisperKitImportIsConfined {
    static func whisperKitImportedOutsideTheEngineIsFlagged() {
        import WhisperKit
    }

    static func hubImportedOutsideTheEngineIsFlagged() {
        import Hub
    }

    static func tokenizersImportedOutsideTheEngineIsFlagged() {
        import Tokenizers
    }

    static func argmaxCoreImportedOutsideTheEngineIsFlagged() {
        import ArgmaxCore
    }

    static func oneTypeImportedFromHubIsFlagged() {
        import struct Hub.HubApi
    }

    static func importNamedInACommentPasses() {
        // import WhisperKit
    }

    static func moduleSharingAPrefixPasses() {
        import HubSpot
    }
}
