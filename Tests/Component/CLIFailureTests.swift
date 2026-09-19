#if os(macOS)
    import Foundation
    import Testing
    import WorkoutTracker

    @testable import WorkoutCLI

    @Test func everyFailureKindHasAnExitCodeTheCLIContractPromises() {
        let exitCodes: [ApplicationError.Kind: Int32] = [.domain: 1, .environment: 3, .conflict: 4]
        for kind in ApplicationError.Kind.allCases {
            #expect(ExitClass(kind).rawValue == exitCodes[kind], "\(kind)")
        }
    }

    @Test func anApplicationErrorReachesTheWireAsItsCodeMessageCandidatesAndExitCode() {
        let notFound = Failure(ApplicationError.notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0"]))
        #expect(notFound.payload.code == "unknown_set")
        #expect(notFound.payload.message == "w1d1.e0 has 1 Sets; no Set at w1d1.e0.s9.")
        #expect(notFound.payload.candidates == ["w1d1.e0.s0"])
        #expect(notFound.exitClass.rawValue == 1)

        #expect(Failure(ApplicationError.notConfigured).exitClass.rawValue == 3)
        #expect(Failure(ApplicationError.syncFailed(.sheetUnreachable)).exitClass.rawValue == 3)
        #expect(Failure(ApplicationError.syncFailed(.writesRefused)).exitClass.rawValue == 4)
    }
#endif
