import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

@MainActor
@Suite
struct SyncStatusBannerGroundTests {
    @Test func theBannerGroundCoversTheTextUnderItOnItsFirstFrame() throws {
        let banner = BannerState()
        let page = BannerOverInk(banner: banner)
            .environment(\.themePalette, Theme.palette(for: .day))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        let inked = try AccessibilityHost.read(page, in: [CGSize(width: 402, height: 120)]) { window in
            let absent = try inkedPixels(in: window, within: Region.insideTheCapsuleRightOfTheLabel)
            withAnimation(.linear(duration: 10)) {
                banner.outcome = .writesQueued(1)
            }
            let firstFrame = try inkedPixels(in: window, within: Region.insideTheCapsuleRightOfTheLabel)
            return (absent: absent, firstFrame: firstFrame)
        }[0]
        #expect(inked.absent == 25_200, "with no banner, the ink under the banner's place shows")
        #expect(
            inked.firstFrame == 0,
            "the ink under the banner showed through its ground on the first frame: \(inked.firstFrame) of 25200 pixels"
        )
    }
}

private enum Region {
    static let insideTheCapsuleRightOfTheLabel = CGRect(x: 220, y: 16, width: 140, height: 20)
}

@MainActor
@Observable
private final class BannerState {
    var outcome = SyncOutcome.clear
}

private struct BannerOverInk: View {
    let banner: BannerState

    var body: some View {
        Rectangle()
            .fill(.black)
            .frame(height: 50)
            .overlay(alignment: .top) {
                SyncStatusBanner(outcome: banner.outcome, isSyncing: false)
                    .padding(.top, 8)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }
}

@MainActor
private func inkedPixels(in window: UIWindow, within region: CGRect) throws -> Int {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    let image = UIGraphicsImageRenderer(bounds: region, format: format).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    let cgImage = try #require(image.cgImage)
    var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
    return try pixels.withUnsafeMutableBytes { bytes in
        let context = try #require(
            CGContext(
                data: bytes.baseAddress,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return stride(from: 0, to: bytes.count, by: 4).filter { offset in
            (0..<3).allSatisfy { bytes[offset + $0] < 64 }
        }
        .count
    }
}
