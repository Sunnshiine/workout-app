import SwiftUI
import Testing

@testable import WorkoutTracker

#if os(iOS)
    @Suite
    struct OKLCHColorTests {
        @Test(arguments: [
            (lightness: 1.0, chroma: 0.0, hue: 0.0, hex: UInt32(0xFFFFFF)),
            (lightness: 0.0, chroma: 0.0, hue: 0.0, hex: UInt32(0x000000)),
            (lightness: 0.2, chroma: 0.03, hue: 156.0, hex: UInt32(0x0A1A10)),
            (lightness: 0.29, chroma: 0.055, hue: 156.0, hex: UInt32(0x10331F)),
            (lightness: 0.95, chroma: 0.025, hue: 156.0, hex: UInt32(0xE2F4E8)),
            (lightness: 0.88, chroma: 0.06, hue: 156.0, hex: UInt32(0xB8E4C7))
        ])
        func anOKLCHColourDrawsAsTheSRGBColourCSSGivesIt(lightness: Double, chroma: Double, hue: Double, hex: UInt32) {
            let drawn = Color(oklchLightness: lightness, chroma: chroma, hue: hue).resolve(in: EnvironmentValues())
            let bytes = [drawn.red, drawn.green, drawn.blue].map { UInt32(($0 * 255).rounded()) }

            #expect(bytes[0] << 16 | bytes[1] << 8 | bytes[2] == hex)
        }
    }
#endif
