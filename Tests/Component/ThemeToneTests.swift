import SwiftUI
import Testing

@testable import WorkoutTracker

@Test func oklchConvertsToTheSRGBTheReferenceConversionGives() {
    let green = srgbComponents(of: Theme.OKLCH(lightness: 0.627, chroma: 0.17, hue: 149.214).color).rgb
    #expect(abs(green.red - 22) <= 1 && abs(green.green - 163) <= 1 && abs(green.blue - 74) <= 1, "rgb(22, 163, 74)")
}

@Test(arguments: Theme.Ramp.allCases)
func everyRampStepShowsInSRGB(ramp: Theme.Ramp) {
    for step in Theme.Step.allCases {
        let tone = ramp.tone(step)
        #expect(tone.isInSRGBGamut, "\(ramp) \(step.rawValue): \(tone)")
    }
}

@Test func theSRGBCeilingSitsOnTheGamutEdge() {
    let ceiling = Theme.OKLCH.sRGBCeiling(lightness: 0.6, hue: 20)
    #expect(Theme.OKLCH(lightness: 0.6, chroma: ceiling, hue: 20).isInSRGBGamut)
    #expect(!Theme.OKLCH(lightness: 0.6, chroma: ceiling + 0.002, hue: 20).isInSRGBGamut)
    #expect(abs(ceiling - 0.241) < 0.003, "Emil's oklch(0.6 0.241 20) is the largest red that renders")
}

@Test func nightMirrorsAnInkAndLiftsAFillOneStep() {
    let ink = Theme.Pigment(.leaf, .s700)
    let fill = Theme.Pigment(.leaf, .s700, .fill)
    #expect(ink.nightTone.lightness == Theme.Step.s300.lightness, "ink 700 reads 300 at Night")
    #expect(fill.nightTone.lightness == Theme.Step.s600.lightness, "fill 700 reads 600 at Night")
    #expect(fill.nightTone.chroma < Theme.Ramp.leaf.tone(.s600).chroma, "Night calms the leaf fill")
}

@Test func nightKeepsEveryPigmentInsideSRGB() {
    for ramp in Theme.Ramp.allCases {
        for step in Theme.Step.allCases {
            #expect(Theme.Pigment(ramp, step).nightTone.isInSRGBGamut, "\(ramp) \(step.rawValue) at Night")
        }
    }
}
