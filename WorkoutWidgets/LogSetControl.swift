import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center, Lock Screen, or Action button control that logs a Set by voice. The intent is
/// a `LiveActivityIntent`, so the system performs it in the app, not here.
struct LogSetControl: ControlWidget {
    static let kind = "com.sunnypatel.WorkoutTracker.LogSetControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogSetByVoiceIntent()) {
                Label("Log a Set", systemImage: "mic")
            }
        }
        .displayName("Log a Set")
        .description("Listens for your Set and logs it, without opening WorkoutTracker.")
    }
}
