import CoreGraphics
import Testing

@testable import WorkoutTracker

@Test func weightValueFrameStaysCenteredInPillBlock() {
    let pillWidth: CGFloat = 216

    let valueFrame = WeightPillLayoutMetrics.valueFrame(in: pillWidth)

    #expect(valueFrame.midX == pillWidth / 2)
    #expect(valueFrame.minX == WeightPillLayoutMetrics.valueSideReserve)
    #expect(valueFrame.maxX == pillWidth - WeightPillLayoutMetrics.valueSideReserve)
}

@Test func weightStepperFramesKeepHitRegionsOutsideCenteredValueFrame() {
    let pillWidth: CGFloat = 216

    let valueFrame = WeightPillLayoutMetrics.valueFrame(in: pillWidth)
    let controls = WeightPillLayoutMetrics.stepperFrames(in: pillWidth)

    #expect(controls.decrement.width == WeightPillLayoutMetrics.stepperButtonSize)
    #expect(controls.increment.width == WeightPillLayoutMetrics.stepperButtonSize)
    #expect(controls.decrement.maxX + WeightPillLayoutMetrics.stepperSpacing == valueFrame.minX)
    #expect(controls.increment.minX - WeightPillLayoutMetrics.stepperSpacing == valueFrame.maxX)
}

@Test func weightValueFrameDoesNotShiftWhenSteppersAreHidden() {
    let pillWidth: CGFloat = 216

    let visibleStepperFrame = WeightPillLayoutMetrics.valueFrame(in: pillWidth, showsSteppers: true)
    let hiddenStepperFrame = WeightPillLayoutMetrics.valueFrame(in: pillWidth, showsSteppers: false)

    #expect(hiddenStepperFrame == visibleStepperFrame)
    #expect(hiddenStepperFrame.midX == pillWidth / 2)
}
