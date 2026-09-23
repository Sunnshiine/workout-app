@MainActor
final class UnstructuredTaskIsHeld {
    private var held: Task<Void, Never>?

    func bareTaskAtLineStartIsFlagged() {
        Task {
            await sync()
        }
    }

    func detachedTaskAtLineStartIsFlagged() {
        Task.detached {
            await sync()
        }
    }

    func taskWithALiteralPriorityAtLineStartIsFlagged() {
        Task(priority: .high) {
            await sync()
        }
    }

    func discardedTaskPasses() {
        _ = Task { await sync() }
    }

    func taskWithExplicitGenericsPasses() {
        Task<Void, Never> {
            await sync()
        }
    }

    func taskAssignedMidLinePasses() {
        let task = Task {
            await sync()
        }
        held = task
    }

    func taskWithAPriorityFromACallPasses() {
        Task(priority: currentPriority()) {
            await sync()
        }
    }

    func taskInABlockCommentPasses() {
        /*
        Task {
            await sync()
        }
        */
    }

    func taskInAMultilineStringPasses() -> String {
        """
        Task {
            await sync()
        }
        """
    }
}
