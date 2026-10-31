import Foundation
import SwiftUI

extension Theme {
    // MARK: - OKLCH

    /// A colour as perceived: `lightness` 0…1, `chroma` from 0 (grey), `hue` in degrees. Contrast
    /// lives in the lightness gap, so a ramp spaces its steps evenly in it (token sheet §2).
    struct OKLCH: Equatable {
        let lightness: Double
        let chroma: Double
        let hue: Double

        /// Linear-light sRGB red, green, blue; a channel outside 0…1 is a colour sRGB cannot show.
        var linearSRGB: SIMD3<Double> {
            let radians = hue * .pi / 180
            let labA = chroma * cos(radians)
            let labB = chroma * sin(radians)
            let long = pow(lightness + 0.3963377774 * labA + 0.2158037573 * labB, 3)
            let medium = pow(lightness - 0.1055613458 * labA - 0.0638541728 * labB, 3)
            let short = pow(lightness - 0.0894841775 * labA - 1.2914855480 * labB, 3)
            return SIMD3(
                4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short,
                -1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short,
                -0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short
            )
        }

        var isInSRGBGamut: Bool {
            let channels = linearSRGB
            return [channels.x, channels.y, channels.z].allSatisfy { (-1e-7...(1 + 1e-7)).contains($0) }
        }

        var color: Color {
            func encoded(_ linear: Double) -> Double {
                let clamped = min(max(linear, 0), 1)
                return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
            }
            assert(isInSRGBGamut, "\(self) lies outside sRGB")
            let channels = linearSRGB
            return Color(.sRGB, red: encoded(channels.x), green: encoded(channels.y), blue: encoded(channels.z))
        }

        /// The most chroma sRGB shows at this lightness and hue.
        static func sRGBCeiling(lightness: Double, hue: Double) -> Double {
            var range = 0.0...0.4
            for _ in 0..<32 {
                let middle = (range.lowerBound + range.upperBound) / 2
                range =
                    OKLCH(lightness: lightness, chroma: middle, hue: hue).isInSRGBGamut
                    ? middle...range.upperBound : range.lowerBound...middle
            }
            return range.lowerBound
        }
    }

    // MARK: - Tonal ramps

    /// A ramp step, 50 the near-white tint and 950 the near-black shade, evenly spaced in lightness.
    enum Step: Int, CaseIterable {
        case s50
        case s100
        case s200
        case s300
        case s400
        case s500
        case s600
        case s700
        case s800
        case s900
        case s950

        var lightness: Double { 0.97 - 0.075 * Double(rawValue) }

        /// The step Night reads for a pigment Day reads at this one: 200 ↔ 800, 300 ↔ 700.
        var mirrored: Step { Self.allCases[Self.allCases.count - 1 - rawValue] }

        /// The share of the sRGB ceiling a chromatic ramp takes here: airy tints, rich shades.
        var ceilingShare: Double {
            [0.35, 0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 0.95, 0.9, 0.8][rawValue]
        }
    }

    /// One hue per ramp, fixed across every step.
    enum Ramp: CaseIterable {
        /// The tinted neutral: text, muted text, quiet marks.
        case sage
        /// The action green: the Log capsule, the branch, the current tile.
        case leaf
        /// The destructive red.
        case ember

        var hue: Double {
            switch self {
            case .sage: 148
            case .leaf: 156
            case .ember: 27
            }
        }

        /// What Night does to the mirror step's chroma. The action green keeps 75%, because at full
        /// chroma it vibrates on the dark paper. Ember takes 1.5×, capped at the ceiling, because
        /// sRGB's red narrows at Night's light steps and danger must still read as red.
        var nightChromaShare: Double {
            switch self {
            case .sage: 1
            case .leaf: 0.75
            case .ember: 1.5
            }
        }

        /// A neutral holds one chroma at every step; a chromatic ramp takes a share of each ceiling.
        var fixedChroma: Double? {
            self == .sage ? 0.024 : nil
        }

        func tone(_ step: Step) -> OKLCH {
            let ceiling = OKLCH.sRGBCeiling(lightness: step.lightness, hue: hue)
            let chroma = fixedChroma.map { min($0, ceiling) } ?? step.ceilingShare * ceiling
            return OKLCH(lightness: step.lightness, chroma: chroma, hue: hue)
        }
    }

    /// A pigment named once and lit for both appearances. An ink or a mark reads the mirror step at
    /// Night. A fill reads one step lighter instead, because a mirrored fill would be the brightest
    /// object on the Night page, and keeps the same text on it.
    enum PigmentUse {
        case ink
        case fill
    }

    struct Pigment {
        let ramp: Ramp
        let step: Step
        let use: PigmentUse

        init(_ ramp: Ramp, _ step: Step, _ use: PigmentUse = .ink) {
            self.ramp = ramp
            self.step = step
            self.use = use
        }

        var nightStep: Step {
            switch use {
            case .ink: step.mirrored
            case .fill: Step.allCases[max(step.rawValue - 1, 0)]
            }
        }

        var dayTone: OKLCH { ramp.tone(step) }

        var nightTone: OKLCH {
            let mirror = ramp.tone(nightStep)
            let ceiling = OKLCH.sRGBCeiling(lightness: mirror.lightness, hue: mirror.hue)
            let chroma = min(mirror.chroma * ramp.nightChromaShare, ceiling)
            return OKLCH(lightness: mirror.lightness, chroma: chroma, hue: mirror.hue)
        }

        var day: Color { dayTone.color }
        var night: Color { nightTone.color }
    }
}

// MARK: - The pigments (token sheet §2)

extension Theme.Pigment {
    static let ink = Self(.sage, .s950)
    static let muted = Self(.sage, .s800)
    static let partnerInk = Self(.sage, .s700)
    static let action = Self(.leaf, .s700)
    static let actionFill = Self(.leaf, .s700, .fill)
    static let actionInk = Self(.leaf, .s800)
    static let tileRim = Self(.leaf, .s600)
    static let danger = Self(.ember, .s800)
}
