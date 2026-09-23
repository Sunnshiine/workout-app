import SwiftUI

struct UnstructuredTaskIsHeld {
    let store: SessionStore

    func taskInAViewPasses() {
        Task {
            await store.refresh()
        }
    }
}
