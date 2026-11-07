import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A small movie with a plate on a known path, written frame by frame, so a tracker's path can be
/// scored against what was drawn. Each frame is a JPEG made here and passed through to the file,
/// because a CI Simulator has no JPEG video encoder. Every frame stands alone, which keeps a seek exact.
enum SyntheticMovie {
    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    static let frameRate: Int32 = 30

    /// `plate` gives the plate's center on each frame, as shares of the displayed frame from its top
    /// left, or nil for a frame where the plate is gone. `transform` is the movie's display rotation;
    /// the stored pixels turn the other way, so what displays stays upright.
    static func write(
        to url: URL,
        frames: Int,
        displayed: CGSize = CGSize(width: 180, height: 320),
        transform: CGAffineTransform = .identity,
        plate: @Sendable (Int) -> Point?
    ) async throws {
        let isTurned = transform.a == 0
        let stored = isTurned ? CGSize(width: displayed.height, height: displayed.width) : displayed
        let format = try formatDescription(of: stored)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
        input.transform = transform
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            try await waitUntilReady(input, of: writer)
            let picture = try jpeg(size: stored, displayed: displayed, transform: transform, center: plate(frame))
            guard input.append(try sample(of: picture, format: format, frame: frame)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
    }

    /// Zeroes the back half of a written movie's frames, so it opens and then fails part way through a read.
    static func damageBackHalf(of url: URL) throws {
        var bytes = try Data(contentsOf: url)
        guard let frames = bytes.range(of: Data("mdat".utf8)), let index = bytes.range(of: Data("moov".utf8)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let end = index.lowerBound - 4
        let middle = (frames.upperBound + end) / 2
        bytes.replaceSubrange(middle..<end, with: Data(count: end - middle))
        try bytes.write(to: url)
    }

    /// The writer drains on its own threads, in real time, so the bound outlasts a host under load.
    private static func waitUntilReady(_ input: AVAssetWriterInput, of writer: AVAssetWriter) async throws {
        for _ in 0..<100_000_000 {
            if input.isReadyForMoreMediaData { return }
            if let error = writer.error { throw error }
            await Task.yield()
        }
        throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "The movie's writer never came ready."])
    }

    private static func formatDescription(of size: CGSize) throws -> CMVideoFormatDescription {
        var made: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_JPEG,
            width: Int32(size.width),
            height: Int32(size.height),
            extensions: nil,
            formatDescriptionOut: &made
        )
        guard let made else { throw CocoaError(.fileWriteUnknown) }
        return made
    }

    private static func sample(of picture: Data, format: CMVideoFormatDescription, frame: Int) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: picture.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: picture.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block
        )
        guard let block else { throw CocoaError(.fileWriteUnknown) }
        picture.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: picture.count)
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: frameRate),
            presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: frameRate),
            decodeTimeStamp: .invalid
        )
        var size = picture.count
        var made: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &made
        )
        guard let made else { throw CocoaError(.fileWriteUnknown) }
        return made
    }

    private static func jpeg(
        size: CGSize,
        displayed: CGSize,
        transform: CGAffineTransform,
        center: Point?
    ) throws -> Data {
        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            )
        else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.84, green: 0.85, blue: 0.81, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 0.6, green: 0.6, blue: 0.56, alpha: 1))
        // Work in the displayed picture, top left origin: this undoes the movie's display rotation.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.concatenate(storedFromDisplayed(transform, stored: size, displayed: displayed))
        context.fill(CGRect(x: 0, y: displayed.height * 0.88, width: displayed.width, height: displayed.height * 0.12))
        if let center {
            drawPlate(
                in: context,
                at: CGPoint(x: center.x * displayed.width, y: center.y * displayed.height),
                radius: displayed.width * 0.15
            )
        }
        let data = NSMutableData()
        guard
            let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

    /// Maps the displayed picture onto the stored pixels, the inverse of what the movie's transform
    /// does to show them.
    private static func storedFromDisplayed(_ transform: CGAffineTransform, stored: CGSize, displayed: CGSize) -> CGAffineTransform {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: stored.height)
        case (0, -1, 1, 0): CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: stored.width, ty: 0)
        default: .identity
        }
    }

    private static func drawPlate(in context: CGContext, at center: CGPoint, radius: CGFloat) {
        let rings: [(CGFloat, CGColor)] = [
            (1, CGColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1)),
            (0.72, CGColor(red: 0.3, green: 0.32, blue: 0.34, alpha: 1)),
            (0.42, CGColor(red: 0.9, green: 0.9, blue: 0.86, alpha: 1)),
            (0.16, CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ]
        for (share, color) in rings {
            context.setFillColor(color)
            let size = radius * share
            context.fillEllipse(in: CGRect(x: center.x - size, y: center.y - size, width: size * 2, height: size * 2))
        }
        context.setFillColor(CGColor(red: 0.95, green: 0.8, blue: 0.2, alpha: 1))
        let size = radius * 0.12
        for spoke in 0..<6 {
            let angle = CGFloat(spoke) * .pi / 3
            let spot = CGPoint(x: center.x + radius * 0.56 * cos(angle), y: center.y + radius * 0.56 * sin(angle))
            context.fillEllipse(in: CGRect(x: spot.x - size, y: spot.y - size, width: size * 2, height: size * 2))
        }
    }
}
