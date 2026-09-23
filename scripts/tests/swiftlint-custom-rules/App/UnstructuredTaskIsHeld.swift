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

    func taskReturnedImplicitlyIsFalselyFlagged() -> Task<Void, Never> {
        Task {
            await sync()
        }
    }

    func taskHeldOnTheLineAfterTheAssignmentIsFalselyFlagged() {
        held =
            Task {
                await sync()
            }
    }

    func discardedTaskIsMissed() {
        _ = Task { await sync() }
    }

    func taskWithExplicitGenericsIsMissed() {
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

    func taskWithAPriorityFromACallIsMissed() {
        Task(priority: currentPriority()) {
            await sync()
        }
    }

    func taskMidLineAfterABraceIsMissed() {
        DispatchQueue.main.async { Task { await sync() } }
    }

    func taskInABlockCommentPasses() {
        /*
        Task {
            await sync()
        }
        */
    }

    func taskInADocCommentPasses() {
        /**
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
