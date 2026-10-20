import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

@MainActor
@Suite
struct ActiveSetCardLayoutTests {
    @Test func everyCardModeDrawsTheSameFourRowsInTheSameCardFrame() throws {
        let rows = CardRows(
            card: CGRect(x: 16, y: 62, width: 370, height: 308),
            head: CGRect(x: 32, y: 78, width: 59, height: 23),
            weight: CGRect(x: 98, y: 117, width: 206, height: 66),
            reps: CGRect(x: 32, y: 199, width: 163, height: 83),
            rpe: CGRect(x: 207, y: 199, width: 163, height: 83),
            action: CGRect(x: 32, y: 298, width: 338, height: 58)
        )
        let clearMenu = ["Clear menu": CGRect(x: 338, y: 68, width: 44, height: 44)]
        let savedAndClearMenu = clearMenu.merging(["Saved": CGRect(x: 278, y: 80, width: 60, height: 20)]) { $1 }
        let mic = ["Mic": CGRect(x: 338, y: 68, width: 44, height: 44)]

        let drawn = try CardHost.drawings(of: [
            "logging a pending Set": CardHost.Scene(state: .pending, mode: .logging),
            "logging a skipped Set": CardHost.Scene(state: .skipped, mode: .logging),
            "logging a logged Set": CardHost.Scene(state: .logged, mode: .logging),
            "reviewing a logged Set": CardHost.Scene(state: .logged, mode: .reviewing(showsSaved: false)),
            "reviewing a logged Set just saved": CardHost.Scene(state: .logged, mode: .reviewing(showsSaved: true)),
            "reviewing an Unstructured Set Log": CardHost.Scene(state: .loggedUnstructured, mode: .reviewing(showsSaved: false)),
            "holding a Set logged by speech": CardHost.Scene(state: .logged, mode: .heldAfterSpokenWrite),
            "holding a Set skipped by speech": CardHost.Scene(state: .skipped, mode: .heldAfterSpokenWrite),
            "logging a pending Set with the mic": CardHost.Scene(state: .pending, mode: .logging, mic: .ready),
            "listening for a pending Set": CardHost.Scene(
                state: .pending,
                mode: .logging,
                mic: .listening(caption: "135 for 4 at RPE 9, and that last rep was a grinder")
            ),
            "showing a press that wrote nothing": CardHost.Scene(
                state: .pending,
                mode: .logging,
                mic: .rejected(caption: "“100 kilos for 5”")
            )
        ])

        #expect(
            drawn == [
                "logging a pending Set": CardDrawing(
                    rows: rows,
                    actionControl: "log-active-set-button",
                    headControls: [:]
                ),
                "logging a skipped Set": CardDrawing(
                    rows: rows,
                    actionControl: "log-active-set-button",
                    headControls: clearMenu
                ),
                "logging a logged Set": CardDrawing(
                    rows: rows,
                    actionControl: "log-active-set-button",
                    headControls: clearMenu
                ),
                "reviewing a logged Set": CardDrawing(
                    rows: rows,
                    actionControl: "logged-set-capsule",
                    headControls: [:]
                ),
                "reviewing a logged Set just saved": CardDrawing(
                    rows: rows,
                    actionControl: "logged-set-capsule",
                    headControls: ["Saved": CGRect(x: 310, y: 80, width: 60, height: 20)]
                ),
                "reviewing an Unstructured Set Log": CardDrawing(
                    rows: rows,
                    actionControl: "logged-set-capsule",
                    headControls: [:]
                ),
                "holding a Set logged by speech": CardDrawing(
                    rows: rows,
                    actionControl: "logged-set-capsule",
                    headControls: savedAndClearMenu
                ),
                "holding a Set skipped by speech": CardDrawing(
                    rows: rows,
                    actionControl: "log-active-set-button",
                    headControls: savedAndClearMenu
                ),
                "logging a pending Set with the mic": CardDrawing(
                    rows: rows,
                    actionControl: "log-active-set-button",
                    headControls: mic
                ),
                "listening for a pending Set": CardDrawing(
                    rows: rows,
                    actionControl: "spoken-set-capsule",
                    headControls: mic
                ),
                "showing a press that wrote nothing": CardDrawing(
                    rows: rows,
                    actionControl: "spoken-set-capsule",
                    headControls: mic
                )
            ]
        )
    }
}

private struct CardRows: Equatable, CustomStringConvertible {
    let card: CGRect?
    let head: CGRect?
    let weight: CGRect?
    let reps: CGRect?
    let rpe: CGRect?
    let action: CGRect?

    init(card: CGRect?, head: CGRect?, weight: CGRect?, reps: CGRect?, rpe: CGRect?, action: CGRect?) {
        self.card = card.map(\.roundedToPoints)
        self.head = head.map(\.roundedToPoints)
        self.weight = weight.map(\.roundedToPoints)
        self.reps = reps.map(\.roundedToPoints)
        self.rpe = rpe.map(\.roundedToPoints)
        self.action = action.map(\.roundedToPoints)
    }

    var description: String {
        [("card", card), ("head", head), ("weight", weight), ("reps", reps), ("rpe", rpe), ("action", action)]
            .map { label, frame in "\(label) \(frame?.pointDescription ?? "none")" }
            .joined(separator: ", ")
    }
}

private struct CardDrawing: Equatable, CustomStringConvertible {
    let rows: CardRows
    let actionControl: String
    let headControls: [String: CGRect]

    init(rows: CardRows, actionControl: String, headControls: [String: CGRect]) {
        self.rows = rows
        self.actionControl = actionControl
        self.headControls = headControls.mapValues(\.roundedToPoints)
    }

    var description: String {
        let controls = headControls.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.pointDescription)" }
        return "\(rows), action control \(actionControl), head controls [\(controls.joined(separator: "; "))]"
    }
}

extension CGRect {
    fileprivate var roundedToPoints: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }

    fileprivate var pointDescription: String {
        "\(Int(minX)),\(Int(minY)) \(Int(width))x\(Int(height))"
    }
}

@MainActor
private enum CardHost {
    enum Mode {
        case logging
        case reviewing(showsSaved: Bool)
        case heldAfterSpokenWrite
    }

    enum SetFill {
        case pending
        case skipped
        case logged
        case loggedUnstructured
    }

    struct Scene {
        let state: SetFill
        let mode: Mode
        var mic: SetCardDictation?
    }

    private static let windowSize = CGSize(width: 402, height: 874)
    private static let actionControls = ["log-active-set-button", "logged-set-capsule", "spoken-set-capsule"]
    private static let headControlNames = [
        "clear-logged-set-menu": "Clear menu",
        "Saved": "Saved",
        "say-set-button": "Mic"
    ]

    static func drawings(of scenes: KeyValuePairs<String, Scene>) throws -> [String: CardDrawing] {
        var drawings: [String: CardDrawing] = [:]
        for (name, scene) in scenes {
            drawings[name] = try drawing(of: scene)
        }
        return drawings
    }

    private static func drawing(of scene: Scene) throws -> CardDrawing {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let lastPerformed = LastPerformedLookupStore(context: scenario.context)
        let exercise = Exercise(name: "Competition Bench Press", coachNote: nil)
        exercise.sets = (0..<5).map { index in
            ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
        }
        let set = exercise.sets[2]
        switch scene.state {
        case .pending:
            break
        case .skipped:
            set.state = .skipped
        case .logged:
            set.state = .logged
            set.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
        case .loggedUnstructured:
            set.state = .logged
            set.unstructuredSetLog = "185 for 5, belt on the last rep, then two paused back-off singles at 205 with straps"
        }
        let mode: SetCardSlot.Mode =
            switch scene.mode {
            case .logging: .logging
            case .reviewing(let showsSaved): .reviewingLogged(showsSavedConfirmation: showsSaved)
            case .heldAfterSpokenWrite: .heldAfterSpokenWrite
            }

        let view = VStack(spacing: 0) {
            ActiveSetCard(
                set: set,
                setOrdinal: 3,
                setCount: 5,
                mode: mode,
                mic: scene.mic.map {
                    SetCardMic(
                        dictation: $0,
                        startsHandsFree: false,
                        start: {},
                        finish: { _ in nil },
                        listenHandsFree: { _ in nil },
                        cancel: {},
                        dismiss: {}
                    )
                },
                onLog: { _ in },
                onSkip: {},
                onDelete: {},
                onTouchWhileHeld: {},
                onClearMenuOpened: {},
                onClearMenuClosed: {}
            )
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .environment(lastPerformed)
        .environment(\.themePalette, Theme.palette(for: .day))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)

        let drawing = try AccessibilityHost.read(view, in: [windowSize], read)[0]
        withExtendedLifetime(exercise) {}
        return drawing
    }

    private static func read(_ window: UIWindow) -> CardDrawing {
        func frame(_ matches: (NSObject) -> Bool) -> CGRect? {
            window.accessibilityFrames(where: matches).first
        }
        let actionElement = window.accessibilityTree.first { actionControls.contains($0.elementIdentifier ?? "") }
        var headControls: [String: CGRect] = [:]
        for element in window.accessibilityTree {
            let names = [element.elementIdentifier, element.accessibilityLabel].compactMap { $0 }
            if let key = names.lazy.compactMap({ headControlNames[$0] }).first {
                headControls[key] = element.drawnFrame
            }
        }
        return CardDrawing(
            rows: CardRows(
                card: frame { $0.elementIdentifier == "active-set-card" },
                head: frame { $0.accessibilityLabel == "Set 3 of 5" },
                weight: frame { $0.elementIdentifier == "weight-pill" },
                reps: frame { $0.accessibilityLabel == "Reps" },
                rpe: frame { $0.accessibilityLabel == "RPE" },
                action: actionElement?.drawnFrame
            ),
            actionControl: actionElement?.elementIdentifier ?? "none",
            headControls: headControls
        )
    }
}
