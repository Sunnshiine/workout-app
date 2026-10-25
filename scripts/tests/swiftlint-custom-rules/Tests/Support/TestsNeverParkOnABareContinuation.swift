enum TestsNeverParkOnABareContinuationInSupport {
    static func continuationInAFakeIsFlagged() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuation.resume()
        }
    }
}
