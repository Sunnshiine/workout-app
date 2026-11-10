import SwiftUI

extension Color {
    /// Björn Ottosson's OKLab to linear sRGB matrices, with the hue in degrees as CSS writes it.
    init(oklchLightness lightness: Double, chroma: Double, hue: Double) {
        let greenRed = chroma * cos(hue * .pi / 180)
        let blueYellow = chroma * sin(hue * .pi / 180)
        let long = pow(lightness + 0.3963377774 * greenRed + 0.2158037573 * blueYellow, 3)
        let medium = pow(lightness - 0.1055613458 * greenRed - 0.0638541728 * blueYellow, 3)
        let short = pow(lightness - 0.0894841775 * greenRed - 1.2914855480 * blueYellow, 3)

        self.init(
            .sRGBLinear,
            red: 4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short,
            green: -1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short,
            blue: -0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short
        )
    }
}
