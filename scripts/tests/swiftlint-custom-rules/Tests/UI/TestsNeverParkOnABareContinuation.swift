enum TestsNeverParkOnABareContinuation {
    static func continuationInUITestsPasses() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuation.resume()
        }
    }
}
