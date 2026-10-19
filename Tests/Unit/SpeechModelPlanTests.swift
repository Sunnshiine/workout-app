import Foundation
import Testing

@testable import WorkoutTracker

typealias ModelStep = SpeechModelPlan.Step

@Test(
    "Every lifecycle decision is a row of the plan",
    arguments: [
        // A launch reads what is on disk. A model not specialized for this OS is specialized now.
        (SpeechModelState.absent, SpeechModelEvent.launched(.none), ModelStep(.absent, .none)),
        (.absent, .launched(.downloaded), ModelStep(.specializing, .start(.specialize))),
        (.absent, .launched(.specialized), ModelStep(.downloaded, .none)),
        // The model downloads only on a network that costs nothing.
        (.absent, .network(.unmetered), ModelStep(.downloading, .start(.download))),
        (.absent, .network(.metered), ModelStep(.waitingForNetwork, .none)),
        (.absent, .network(.offline), ModelStep(.waitingForNetwork, .none)),
        (.waitingForNetwork, .network(.unmetered), ModelStep(.downloading, .start(.download))),
        (.waitingForNetwork, .network(.metered), ModelStep(.waitingForNetwork, .none)),
        (.downloading, .network(.metered), ModelStep(.waitingForNetwork, .stopDownload)),
        (.downloading, .network(.offline), ModelStep(.waitingForNetwork, .stopDownload)),
        (.downloading, .network(.unmetered), ModelStep(.downloading, .none)),
        (.ready, .network(.metered), ModelStep(.ready, .none)),
        // Each step leads to the next, and a failure waits for the next launch.
        (.downloading, .finished(.download, succeeded: true), ModelStep(.specializing, .start(.specialize))),
        (.downloading, .finished(.download, succeeded: false), ModelStep(.failed(.download), .none)),
        (.specializing, .finished(.specialize, succeeded: true), ModelStep(.downloaded, .none)),
        (.specializing, .finished(.specialize, succeeded: false), ModelStep(.failed(.specialize), .none)),
        (.loading, .finished(.load, succeeded: true), ModelStep(.ready, .none)),
        (.loading, .finished(.load, succeeded: false), ModelStep(.failed(.load), .none)),
        // Work the model moved on from changes nothing: a download stopped for the network, a load
        // a memory warning stopped.
        (.waitingForNetwork, .finished(.download, succeeded: false), ModelStep(.waitingForNetwork, .none)),
        (.unloaded(.memoryWarning), .finished(.load, succeeded: true), ModelStep(.unloaded(.memoryWarning), .none)),
        // A press loads a model out of memory, and nothing else.
        (.downloaded, .pressBegan, ModelStep(.loading, .start(.load))),
        (.unloaded(.idle), .pressBegan, ModelStep(.loading, .start(.load))),
        (.unloaded(.tooHot), .pressBegan, ModelStep(.loading, .start(.load))),
        (.ready, .pressBegan, ModelStep(.ready, .none)),
        (.loading, .pressBegan, ModelStep(.loading, .none)),
        (.downloading, .pressBegan, ModelStep(.downloading, .none)),
        (.failed(.load), .pressBegan, ModelStep(.failed(.load), .none)),
        // Memory, idleness, and heat let a loaded or loading model go.
        (.ready, .pressure(.memoryWarning), ModelStep(.unloaded(.memoryWarning), .unload)),
        (.ready, .pressure(.idle), ModelStep(.unloaded(.idle), .unload)),
        (.loading, .pressure(.tooHot), ModelStep(.unloaded(.tooHot), .unload)),
        (.downloaded, .pressure(.memoryWarning), ModelStep(.downloaded, .none)),
        (.specializing, .pressure(.memoryWarning), ModelStep(.specializing, .none))
    ] as [(SpeechModelState, SpeechModelEvent, ModelStep)]
)
func everyLifecycleDecisionIsARowOfThePlan(state: SpeechModelState, event: SpeechModelEvent, step: ModelStep) {
    #expect(SpeechModelPlan.next(state, on: event) == step)
}

@Test func everyModelStateReadsBackAsWrittenUnderItsOwnName() throws {
    let names = SpeechModelState.allCases.map(\.name)

    #expect(Set(names).count == SpeechModelState.allCases.count)
    #expect(names.contains("unloaded.memoryWarning"))
    #expect(names.contains("failed.download"))
    #expect(names.contains("waitingForNetwork"))
    for state in SpeechModelState.allCases {
        let json = try JSONEncoder().encode(state)
        #expect(String(bytes: json, encoding: .utf8) == "\"\(state.name)\"")
        #expect(try JSONDecoder().decode(SpeechModelState.self, from: json) == state)
    }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(SpeechModelState.self, from: Data(#""warm""#.utf8)) }
}

@Test(
    "The Settings row names where the model stands",
    arguments: [
        (SpeechModelState.absent, 0.0, "Not downloaded"),
        (.waitingForNetwork, 0, "Waiting for Wi-Fi"),
        (.downloading, 0.429, "Downloading 42%"),
        (.downloading, 1, "Downloading 100%"),
        (.specializing, 0, "Preparing"),
        (.downloaded, 0, "Downloaded"),
        (.unloaded(.idle), 0, "Downloaded"),
        (.loading, 0, "Loading"),
        (.ready, 0.5, "Ready"),
        (.failed(.download), 0, "Couldn’t download"),
        (.failed(.load), 0, "Couldn’t load")
    ] as [(SpeechModelState, Double, String)]
)
func theSettingsRowNamesWhereTheModelStands(state: SpeechModelState, fraction: Double, caption: String) {
    #expect(SpeechModelPlan.caption(state, downloaded: fraction) == caption)
}

@Test func everyModelStateHasWordsForTheSettingsRow() {
    for state in SpeechModelState.allCases {
        #expect(!SpeechModelPlan.caption(state, downloaded: 0).isEmpty, "\(state.name)")
    }
}
