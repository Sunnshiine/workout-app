#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private struct ImagePixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    let image: CGImage
}

private enum DiffError: Error, CustomStringConvertible {
    case usage
    case cannotLoad(String)
    case cannotRender(String)
    case cannotWrite(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: visual-baseline-diff.swift <old.png> <new.png> <out.png>"
        case let .cannotLoad(path):
            return "cannot load image: \(path)"
        case let .cannotRender(path):
            return "cannot render RGBA pixels: \(path)"
        case let .cannotWrite(path):
            return "cannot write diff image: \(path)"
        }
    }
}

private func loadPixels(from path: String) throws -> ImagePixels {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw DiffError.cannotLoad(path)
    }

    let width = image.width
    let height = image.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw DiffError.cannotRender(path)
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ImagePixels(width: width, height: height, bytes: bytes, image: image)
}

private func makeDiffImage(old: ImagePixels, new: ImagePixels) throws -> NSImage {
    let panelWidth = max(old.width, new.width)
    let panelHeight = max(old.height, new.height)
    let labelHeight = 32
    let gutter = 16
    let canvasSize = NSSize(
        width: panelWidth * 3 + gutter * 2,
        height: panelHeight + labelHeight
    )

    let image = NSImage(size: canvasSize)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.white.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    draw(label: "OLD", x: 0, y: panelHeight, width: panelWidth, height: labelHeight)
    draw(label: "NEW", x: panelWidth + gutter, y: panelHeight, width: panelWidth, height: labelHeight)
    draw(label: "DIFF", x: (panelWidth + gutter) * 2, y: panelHeight, width: panelWidth, height: labelHeight)

    NSGraphicsContext.current?.cgContext.draw(
        old.image,
        in: CGRect(x: 0, y: 0, width: old.width, height: old.height)
    )
    NSGraphicsContext.current?.cgContext.draw(
        new.image,
        in: CGRect(x: panelWidth + gutter, y: 0, width: new.width, height: new.height)
    )

    let diff = try makeDiffPanel(old: old, new: new, width: panelWidth, height: panelHeight)
    NSGraphicsContext.current?.cgContext.draw(
        diff,
        in: CGRect(x: (panelWidth + gutter) * 2, y: 0, width: panelWidth, height: panelHeight)
    )

    return image
}

private func draw(label: String, x: Int, y: Int, width: Int, height: Int) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 14),
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraph
    ]
    label.draw(
        in: NSRect(x: x, y: y + 8, width: width, height: height - 8),
        withAttributes: attributes
    )
}

private func makeDiffPanel(old: ImagePixels, new: ImagePixels, width: Int, height: Int) throws -> CGImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var diffBytes = [UInt8](repeating: 255, count: height * bytesPerRow)

    for y in 0..<height {
        for x in 0..<width {
            let output = y * bytesPerRow + x * bytesPerPixel
            guard x < old.width, y < old.height, x < new.width, y < new.height else {
                diffBytes[output] = 255
                diffBytes[output + 1] = 0
                diffBytes[output + 2] = 0
                diffBytes[output + 3] = 255
                continue
            }

            let oldIndex = y * old.width * bytesPerPixel + x * bytesPerPixel
            let newIndex = y * new.width * bytesPerPixel + x * bytesPerPixel
            let changed = old.bytes[oldIndex] != new.bytes[newIndex]
                || old.bytes[oldIndex + 1] != new.bytes[newIndex + 1]
                || old.bytes[oldIndex + 2] != new.bytes[newIndex + 2]
                || old.bytes[oldIndex + 3] != new.bytes[newIndex + 3]

            if changed {
                diffBytes[output] = 255
                diffBytes[output + 1] = 0
                diffBytes[output + 2] = 0
                diffBytes[output + 3] = 255
            }
        }
    }

    guard let provider = CGDataProvider(data: Data(diffBytes) as CFData),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: bytesPerRow,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          )
    else {
        throw DiffError.cannotRender("diff panel")
    }

    return image
}

private func writePNG(_ image: NSImage, to path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw DiffError.cannotWrite(path)
    }

    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: path).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: URL(fileURLWithPath: path), options: .atomic)
}

do {
    guard CommandLine.arguments.count == 4 else {
        throw DiffError.usage
    }

    let old = try loadPixels(from: CommandLine.arguments[1])
    let new = try loadPixels(from: CommandLine.arguments[2])
    let diff = try makeDiffImage(old: old, new: new)
    try writePNG(diff, to: CommandLine.arguments[3])
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
