enum UnstructuredTaskIsHeld {
    static func bareTaskAtLineStartIsFlagged() {
        Task {
            await flush()
        }
    }
}
