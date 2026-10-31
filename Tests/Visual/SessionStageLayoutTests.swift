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
                    name: CGRect(x: 16, y: 133, width: 173, height: 36),
                    partner: nil,
                    note: CGRect(x: 16, y: 183, width: 270, height: 23),
                    leaves: [
                        CGRect(x: 272, y: 234, width: 44, height: 44),
                        CGRect(x: 196, y: 255, width: 44, height: 44),
                        CGRect(x: 120, y: 282, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 430, width: 370, height: 47),
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
                    cadence: CGRect(x: 16, y: 133, width: 36, height: 17),
                    name: CGRect(x: 16, y: 164, width: 123, height: 36),
                    partner: CGRect(x: 16, y: 204, width: 131, height: 25),
                    note: CGRect(x: 16, y: 242, width: 262, height: 23),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                )
        )
    }

    // Type stops following the text size at its cap (DESIGN.md §3 The Product Scale Rule),
    // because there both stages still keep every line and the card on one full-height page.
    @Test func atTheTypeCeilingBothStagesKeepEveryLineOnOnePage() throws {
        for stage in [StageKind.exercise, .superset] {
            let page = try SessionPageHost.layout(
                stage,
                banner: .clear,
                windowHeight: WindowHeight.iPhone17Pro,
                dynamicTypeSize: Theme.TypeScale.largestSize
            )
            #expect(page.note != nil, "\(stage) dropped its coach note")
            #expect(page.branchIsDrawn, "\(stage) dropped its branch")
            let card = try #require(page.card)
            let stageFrame = try #require(page.stage)
            #expect(card.maxY <= stageFrame.maxY, "\(stage) pushed the card off the page")
            if stage == .exercise {
                #expect(page.lastPerformed != nil, "the Exercise stage dropped Last Performed")
            } else {
                #expect(page.cadence != nil, "the Superset stage dropped its Cadence line")
                #expect(page.partner != nil, "the Superset stage dropped its partner")
            }
        }
    }

    @Test func aSyncBannerMovesNothingAndClearsTheExerciseName() throws {
        let heights = [WindowHeight.iPhone17Pro, WindowHeight.mini, WindowHeight.se]
        let banners: [(outcome: SyncOutcome, frames: [CGRect])] = [
            (
                .writesQueued(1),
                [
                    CGRect(x: 16, y: 70, width: 370, height: 35),
                    CGRect(x: 16, y: 70, width: 370, height: 35),
                    CGRect(x: 16, y: 70, width: 370, height: 35)
                ]
            ),
            (
                .writesRefused(["x"]),
                [
                    CGRect(x: 16, y: 70, width: 370, height: 35),
                    CGRect(x: 16, y: 70, width: 370, height: 35),
                    CGRect(x: 16, y: 70, width: 370, height: 35)
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
                    name: CGRect(x: 16, y: 133, width: 173, height: 36),
                    partner: nil,
                    note: CGRect(x: 16, y: 183, width: 270, height: 23),
                    leaves: [
                        CGRect(x: 272, y: 234, width: 44, height: 44),
                        CGRect(x: 196, y: 255, width: 44, height: 44),
                        CGRect(x: 120, y: 282, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 383, width: 370, height: 47),
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
                    cadence: CGRect(x: 16, y: 133, width: 36, height: 17),
                    name: CGRect(x: 16, y: 164, width: 123, height: 36),
                    partner: CGRect(x: 16, y: 204, width: 131, height: 25),
                    note: CGRect(x: 16, y: 242, width: 262, height: 23),
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
                    name: CGRect(x: 16, y: 133, width: 173, height: 36),
                    partner: nil,
                    note: CGRect(x: 16, y: 183, width: 270, height: 23),
                    leaves: [
                        CGRect(x: 272, y: 226, width: 44, height: 44),
                        CGRect(x: 196, y: 233, width: 44, height: 44),
                        CGRect(x: 120, y: 244, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 299, width: 370, height: 47),
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
                    cadence: CGRect(x: 16, y: 133, width: 36, height: 17),
                    name: CGRect(x: 16, y: 164, width: 370, height: 73),
                    partner: nil,
                    note: CGRect(x: 16, y: 251, width: 362, height: 90),
                    leaves: leaves(at: [(280, 364), (251, 368), (222, 373), (193, 378), (164, 384), (134, 391), (105, 398), (76, 406)]),
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 370, height: 73),
                    partner: nil,
                    note: nil,
                    leaves: leaves(at: [(280, 229), (251, 233), (222, 238), (193, 244), (164, 250), (134, 257), (105, 265), (76, 274)]),
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
                    cadence: CGRect(x: 16, y: 133, width: 36, height: 17),
                    name: CGRect(x: 16, y: 164, width: 370, height: 73),
                    partner: CGRect(x: 16, y: 240, width: 362, height: 25),
                    note: CGRect(x: 16, y: 279, width: 362, height: 90),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 370, height: 73),
                    partner: CGRect(x: 16, y: 209, width: 362, height: 25),
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
                    name: CGRect(x: 16, y: 133, width: 173, height: 36),
                    partner: nil,
                    note: CGRect(x: 16, y: 183, width: 270, height: 23),
                    leaves: [
                        CGRect(x: 272, y: 228, width: 44, height: 44),
                        CGRect(x: 196, y: 238, width: 44, height: 44),
                        CGRect(x: 120, y: 252, width: 44, height: 44)
                    ],
                    branchIsDrawn: true,
                    lastPerformed: nil,
                    card: CGRect(x: 16, y: 330, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 597),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 173, height: 36),
                    partner: nil,
                    note: nil,
                    leaves: [
                        CGRect(x: 272, y: 191, width: 44, height: 44),
                        CGRect(x: 196, y: 202, width: 44, height: 44),
                        CGRect(x: 120, y: 216, width: 44, height: 44)
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
                    cadence: CGRect(x: 16, y: 133, width: 36, height: 17),
                    name: CGRect(x: 16, y: 164, width: 123, height: 36),
                    partner: CGRect(x: 16, y: 204, width: 131, height: 25),
                    note: CGRect(x: 16, y: 242, width: 262, height: 23),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 430, width: 370, height: 47),
                    card: CGRect(x: 16, y: 476, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 731),
                    cadence: CGRect(x: 16, y: 133, width: 36, height: 17),
                    name: CGRect(x: 16, y: 164, width: 123, height: 36),
                    partner: CGRect(x: 16, y: 204, width: 131, height: 25),
                    note: CGRect(x: 16, y: 242, width: 262, height: 23),
                    leaves: [],
                    branchIsDrawn: true,
                    lastPerformed: CGRect(x: 16, y: 383, width: 370, height: 47),
                    card: CGRect(x: 16, y: 429, width: 370, height: 308)
                ),
                PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 647),
                    cadence: nil,
                    name: CGRect(x: 16, y: 133, width: 123, height: 36),
                    partner: CGRect(x: 16, y: 172, width: 131, height: 25),
                    note: CGRect(x: 16, y: 211, width: 262, height: 23),
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
