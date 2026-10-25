enum TestsNeverParkOnABareContinuation {
    static func checkedContinuationIsFlagged() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuation.resume()
        }
    }

    static func checkedThrowingContinuationIsFlagged() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            continuation.resume()
        }
    }

    static func unsafeContinuationIsFlagged() async {
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            continuation.resume()
        }
    }

    static func unsafeThrowingContinuationIsFlagged() async throws {
        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
            continuation.resume()
        }
    }

    static func storedContinuationTypeIsMissed() -> [CheckedContinuation<Void, Never>] {
        []
    }

    static func asyncStreamContinuationIsMissed() -> AsyncStream<Int>.Continuation {
        AsyncStream.makeStream(of: Int.self).continuation
    }

    static func continuationInACommentPasses() {
        // await withCheckedContinuation { parked = $0 }
    }

    static func continuationInADocCommentPasses() {
        /// await withCheckedContinuation { parked = $0 }
    }

    static func continuationInAStringPasses() -> String {
        "withCheckedContinuation"
    }
}
