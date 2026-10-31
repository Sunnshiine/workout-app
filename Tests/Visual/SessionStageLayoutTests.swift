import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

@MainActor
@Suite
struct SessionStageLayoutTests {
    @Test func theExerciseBranchStaysDrawnInAFullHeightWindow() throws {
        let page = try SessionPageHost.layout(.exercise, banner: .clear, windowHeight: WindowHeight.iPhone17Pro)
        #expect(
            page
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 188, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 238, width: 44, height: 44),
                        CGRect(x: 196, y: 259, width: 44, height: 44),
                        CGRect(x: 120, y: 286, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 430, width: 370, height: 46),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
    }

    @Test func theSupersetStageKeepsItsBranchInAFullHeightWindow() throws {
        let page = try SessionPageHost.layout(.superset, banner: .clear, windowHeight: WindowHeight.iPhone17Pro)
        #expect(
            page
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: CGRect(x: 16, y: 133, width: 32, height: 16),
                    name: CGRect(x: 16, y: 163, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 207, width: 131, height: 25),
                    note: CGRect(x: 16, y: 245, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
    }

    @Test func aSyncBannerMovesNothingAndClearsTheExerciseName() throws {
        let heights = [WindowHeight.iPhone17Pro, WindowHeight.mini, WindowHeight.se]
        let banners: [(outcome: SyncOutcome, frames: [CGRect])] = [
            (
                .writesQueued(1),
                [
                    CGRect(x: 16, y: 70, width: 370, height: 34),
                    CGRect(x: 16, y: 70, width: 370, height: 34),
                    CGRect(x: 16, y: 70, width: 370, height: 34)
                ]
            ),
            (
                .writesRefused(["x"]),
                [
                    CGRect(x: 16, y: 70, width: 370, height: 34),
                    CGRect(x: 16, y: 70, width: 370, height: 34),
                    CGRect(x: 16, y: 70, width: 370, height: 34)
                ]
            )
        ]
        for stage in [StageKind.exercise, .superset] {
            let clear = try SessionPageHost.layouts(stage, banner: .clear, windowHeights: heights)
            for banner in banners {
                let pages = try SessionPageHost.layouts(stage, banner: banner.outcome, windowHeights: heights)
                #expect(pages.map(\.banner) == banner.frames, "\(stage) page under \(banner.outcome)")
                #expect(pages.map(\.withoutBanner) == clear, "\(stage) page under \(banner.outcome)")
                for page in pages {
                    let bannerFrame = try #require(page.banner)
                    let name = try #require(page.name)
                    #expect(!bannerFrame.intersects(name), "\(stage) page under \(banner.outcome): \(page)")
                }
            }
        }
    }

    @Test func aMiniHeightWindowKeepsLastPerformedAndTheBranch() throws {
        let page = try SessionPageHost.layout(.exercise, banner: .clear, windowHeight: WindowHeight.mini)
        #expect(
            page
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 731),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 188, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 238, width: 44, height: 44),
                        CGRect(x: 196, y: 258, width: 44, height: 44),
                        CGRect(x: 120, y: 286, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 383, width: 370, height: 46),
                    card: CGRect(x: 16, y: 429, width: 370, height: 308)
                )
        )
    }

    @Test func aMiniHeightWindowKeepsTheSupersetsCadenceNoteAndBranch() throws {
        let page = try SessionPageHost.layout(.superset, banner: .clear, windowHeight: WindowHeight.mini)
        #expect(
            page
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 731),
                    cadence: CGRect(x: 16, y: 133, width: 32, height: 16),
                    name: CGRect(x: 16, y: 163, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 207, width: 131, height: 25),
                    note: CGRect(x: 16, y: 245, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 429, width: 370, height: 308)
                )
        )
    }

    @Test func anSEHeightWindowKeepsTheNoteLastPerformedAndTheBranch() throws {
        let page = try SessionPageHost.layout(.exercise, banner: .clear, windowHeight: WindowHeight.se)
        #expect(
            page
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 188, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 229, width: 44, height: 44),
                        CGRect(x: 196, y: 236, width: 44, height: 44),
                        CGRect(x: 120, y: 246, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 299, width: 370, height: 46),
                    card: CGRect(x: 16, y: 345, width: 370, height: 308)
                )
        )
    }

    // The `worst-case` workbook's four-line name took the Cadence line and the coach note off the
    // full-height page and the branch off the SE-height one, the stage's only drawing of Set progress.
    @Test func theWorstCaseNameKeepsToTwoLinesAndLeavesTheBranchOnEveryHeight() throws {
        let heights = [WindowHeight.iPhone17Pro, WindowHeight.se]
        // Eight leaves sit 29pt apart, so each tap area narrows to that share (BranchNodeLayout.hitWidths).
        func leaves(at points: [(x: Int, y: Int)]) -> [CGRect] {
            points.map { CGRect(x: $0.x, y: $0.y, width: 29, height: 44) }
        }
        let exercise = try SessionPageHost.worstCaseLayouts(.exercise, windowHeights: heights)
        let superset = try SessionPageHost.worstCaseLayouts(.superset, windowHeights: heights)

        #expect(
            exercise == [
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: CGRect(x: 16, y: 133, width: 32, height: 16),
                    name: CGRect(x: 16, y: 163, width: 370, height: 69),
                    partner: nil,
                    note: CGRect(x: 16, y: 245, width: 362, height: 98),
                    leaves: leaves(at: [(280, 366), (251, 370), (222, 374), (193, 379), (164, 385), (134, 392), (105, 399), (76, 407)]),
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 370, height: 69),
                    partner: nil,
                    note: nil,
                    leaves: leaves(at: [(280, 225), (251, 230), (222, 235), (193, 241), (164, 248), (134, 255), (105, 263), (76, 272)]),
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 345, width: 370, height: 308)
                )
            ]
        )
        #expect(
            superset == [
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: CGRect(x: 16, y: 133, width: 32, height: 16),
                    name: CGRect(x: 16, y: 163, width: 370, height: 69),
                    partner: CGRect(x: 16, y: 234, width: 362, height: 25),
                    note: CGRect(x: 16, y: 273, width: 362, height: 98),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 370, height: 69),
                    partner: CGRect(x: 16, y: 205, width: 362, height: 25),
                    note: nil,
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 345, width: 370, height: 308)
                )
            ]
        )
    }

    @Test func aRunningRestLeavesTheExerciseAndSupersetPagesWhereTheyWere() throws {
        for stage in [StageKind.exercise, .superset] {
            let resting = try SessionPageHost.layout(stage, banner: .clear, windowHeight: WindowHeight.iPhone17Pro)
            let notResting = try SessionPageHost.layout(
                stage,
                banner: .clear,
                windowHeight: WindowHeight.iPhone17Pro,
                isResting: false
            )
            #expect(resting == notResting, "\(stage) page")
        }
    }
}

@MainActor
@Suite
struct SessionStageLadderTransitionTests {
    @Test func shrinkingTheWindowDropsTheCoachNoteBeforeTheBranch() throws {
        let pages = try SessionPageHost.layouts(
            .exercise,
            banner: .clear,
            windowHeights: [WindowHeight.noteRung, WindowHeight.nameAndBranchRung]
        )
        #expect(
            pages == [
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 632),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: CGRect(x: 16, y: 188, width: 270, height: 22),
                    leaves: [
                        CGRect(x: 272, y: 231, width: 44, height: 44),
                        CGRect(x: 196, y: 241, width: 44, height: 44),
                        CGRect(x: 120, y: 254, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 330, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 597),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    partner: nil,
                    note: nil,
                    leaves: [
                        CGRect(x: 272, y: 195, width: 44, height: 44),
                        CGRect(x: 196, y: 205, width: 44, height: 44),
                        CGRect(x: 120, y: 219, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 295, width: 370, height: 308)
                )
            ]
        )
    }

    @Test func shrinkingTheWindowDropsEveryLineTheShorterRungGivesUp() throws {
        let pages = try SessionPageHost.layouts(
            .superset,
            banner: .clear,
            windowHeights: [WindowHeight.iPhone17Pro, WindowHeight.mini, WindowHeight.se],
            history: History.backSquatAndBBRDL()
        )
        #expect(
            pages == [
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    cadence: CGRect(x: 16, y: 133, width: 32, height: 16),
                    name: CGRect(x: 16, y: 163, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 207, width: 131, height: 25),
                    note: CGRect(x: 16, y: 245, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 430, width: 370, height: 46),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 731),
                    cadence: CGRect(x: 16, y: 133, width: 32, height: 16),
                    name: CGRect(x: 16, y: 163, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 207, width: 131, height: 25),
                    note: CGRect(x: 16, y: 245, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 383, width: 370, height: 46),
                    card: CGRect(x: 16, y: 429, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 123, height: 41),
                    partner: CGRect(x: 16, y: 177, width: 131, height: 25),
                    note: CGRect(x: 16, y: 216, width: 262, height: 22),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 345, width: 370, height: 308)
                )
            ]
        )
    }

    @Test func shrinkingTheCompletionStageDropsTheOpenExercisesAndKeepsMoveOn() throws {
        let heights: [CGFloat] = [WindowHeight.iPhone17Pro, 300]
        let pages = try SessionPageHost.completionPages(windowHeights: heights)
        #expect(
            pages.map(\.labels) == [
                [
                    "Session complete", "1 Set across 1 Exercise", "Open Exercises",
                    "Back Squat, 1 Set left, W1 D1", "Move On", "Queue"
                ],
                ["Session complete", "1 Set across 1 Exercise", "Move On", "Queue"]
            ]
        )
        for (page, height) in zip(pages, heights) {
            let window = CGRect(x: 0, y: 0, width: 402, height: height)
            #expect(page.moveOn.map(window.contains) == true, "Move On lies inside the \(Int(height))pt window")
        }
    }
}
