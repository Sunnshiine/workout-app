import CoreGraphics

struct WeightPillLayoutMetrics: Equatable, Sendable {
    struct StepperFrames: Equatable, Sendable {
        let decrement: CGRect
        let increment: CGRect
    }

    static let stepperButtonSize: CGFloat = 36
    static let stepperSpacing: CGFloat = 8
    static var valueSideReserve: CGFloat {
        stepperButtonSize + stepperSpacing
    }

    static func valueFrame(in width: CGFloat) -> CGRect {
        valueFrame(in: width, showsSteppers: true)
    }

    static func valueFrame(in width: CGFloat, showsSteppers _: Bool) -> CGRect {
        let sideReserve = min(valueSideReserve, max(width / 2, 0))
        let valueWidth = max(width - sideReserve * 2, 0)
        return CGRect(x: sideReserve, y: 0, width: valueWidth, height: stepperButtonSize)
    }

    static func stepperFrames(in width: CGFloat) -> StepperFrames {
        StepperFrames(
            decrement: CGRect(x: 0, y: 0, width: stepperButtonSize, height: stepperButtonSize),
            increment: CGRect(
                x: max(width - stepperButtonSize, 0),
                y: 0,
                width: stepperButtonSize,
                height: stepperButtonSize
            )
        )
    }
}
