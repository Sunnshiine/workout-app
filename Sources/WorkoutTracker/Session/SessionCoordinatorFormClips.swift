import Foundation

/// What the card offers for a Set that can hold a Form Clip.
struct SetCardClips: Equatable {
    let target: FormClipTarget
    /// Newest first. Empty offers Add Clip, any offers the review.
    let clips: [FormClip]
    /// A pick is on its way in, so the card shows it working.
    let isAdding: Bool
}

enum FormClipSource: Equatable, Sendable {
    case camera
    case photos
}

/// The one thing the stage presents over itself for a Form Clip.
enum FormClipRequest: Equatable, Identifiable {
    case add(FormClipTarget, FormClipSource)
    case review(UUID)

    var id: String {
        switch self {
        case .add(let target, .camera): "camera \(target.setID)"
        case .add(let target, .photos): "photos \(target.setID)"
        case .review(let id): id.uuidString
        }
    }
}

extension FormClipError {
    /// What the athlete reads when a pick does not become a clip.
    var failureMessage: String {
        switch self {
        case .notAMovie: "That file isn't a movie this phone can play."
        case .noSuchClip: "That clip is no longer on this phone."
        case .setNotLogged: "A clip attaches to a Logged Set."
        case .noSheet: "Connect a Training Sheet first."
        }
    }
}

extension SessionCoordinator {
    /// Nil keeps clips off the card: a Set that is not Logged, including a Skipped one, whose capsule
    /// says the athlete did not perform it, or with no Sheet to name it by.
    func cardClips(for slot: SetCardSlot) -> SetCardClips? {
        guard let spreadsheetId = wiring.spreadsheetId(), let target = FormClipTarget(slot.set, spreadsheetId: spreadsheetId) else {
            return nil
        }
        return SetCardClips(
            target: target,
            clips: wiring.formClips.clips(on: target.setID, in: target.spreadsheetId),
            isAdding: addingClipTo == target.setID
        )
    }

    /// Takes the target rather than the slot, because a held card moves on as its menu closes.
    func requestClip(from source: FormClipSource, for target: FormClipTarget) {
        clipRequest = .add(target, source)
    }

    /// Add another from inside a review, on the clip's own Set, whatever the card shows by now.
    func requestClip(from source: FormClipSource, for clip: FormClip) {
        clipRequest = .add(FormClipTarget(clip), source)
    }

    func showClip(_ id: UUID) {
        clipRequest = .review(id)
    }

    func closeClipRequest() {
        clipRequest = nil
    }

    func dismissClipFailure() {
        clipFailure = nil
    }

    /// Closes the picker, brings the movie in while the card shows it working, then opens the review
    /// on it. `loading` hands over a movie the library may move, or nil when the athlete picked
    /// nothing.
    func addClip(to target: FormClipTarget, loading: @escaping @Sendable () async throws -> URL?) {
        clipRequest = nil
        addingClipTo = target.setID
        clipAdding?.cancel()
        clipAdding = Task { [weak self] in
            do {
                guard let movie = try await loading() else {
                    self?.addingClipTo = nil
                    return
                }
                guard let self else { return }
                let clip = try await wiring.formClips.add(moving: movie, to: target)
                addingClipTo = nil
                clipRequest = .review(clip.id)
            } catch {
                self?.addingClipTo = nil
                self?.clipFailure = (error as? FormClipError)?.failureMessage ?? "That clip couldn't be saved. Try it again."
            }
        }
    }
}
