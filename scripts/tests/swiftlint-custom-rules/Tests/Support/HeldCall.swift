enum HeldCall {
    static func continuationInHeldCallPasses() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuation.resume()
        }
    }
}
