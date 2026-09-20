#!/usr/bin/env swift
// usage: scripts/contact-sheet.swift OUT.png IMAGE...
//
// Tiles images into one PNG sized for a model to read in a single Read call. More than 12 images
// become balanced pages: OUT.png, OUT-2.png, and so on. Prints one line per page:
//   <path> TAB <width>x<height> TAB <n> images TAB about <t> tokens TAB 1. <stem>  2. <stem>  ...
// Exit 64 on bad usage, 66 when an image cannot be read, 73 when a page cannot be written.

import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// How a Claude-class reader sees an image. These are facts about the reader rather than
/// preferences of a caller, which is why this tool takes no options.
enum Reader {
    /// Read downsizes every image to this long edge, so pixels past it are paid for and discarded.
    static let longEdge = 2000
    /// At 12-up (324 px cells) Opus and Sonnet read every string. At 20-up (191 px cells) Sonnet
    /// misread digits without flagging doubt.
    static let cellsPerSheet = 12
    static let patch = 28
}

enum Style {
    static let gutter: CGFloat = 8
    static let labelHeight: CGFloat = 28
    static let labelFontSize: CGFloat = 16
    static let background = CGColor(gray: 0.12, alpha: 1)
}

enum Failure: Error {
    case usage
    case unreadable(path: String)
    case unwritable(path: String)

    var exitCode: Int32 {
        switch self {
        case .usage: 64
        case .unreadable: 66
        case .unwritable: 73
        }
    }

    var message: String {
        switch self {
        case .usage: "usage: contact-sheet.swift OUT.png IMAGE..."
        case .unreadable(let path): "cannot read image: \(path)"
        case .unwritable(let path): "cannot write page: \(path)"
        }
    }
}

struct Cell {
    let label: String
    let image: CGImage
}

struct Grid {
    let columns: Int
    let rows: Int
    let cell: CGSize
    let sheet: CGSize
}

/// Balanced so the last page is not a stub: 13 becomes 7 and 6, 25 becomes 9, 8 and 8. A 12 and 1
/// split would put 324 px cells on one page and a 899 px cell on the next.
func pages(of count: Int) -> [Range<Int>] {
    let pageCount = (count + Reader.cellsPerSheet - 1) / Reader.cellsPerSheet
    var ranges: [Range<Int>] = []
    var start = 0
    for page in 0..<pageCount {
        let size = count / pageCount + (page < count % pageCount ? 1 : 0)
        ranges.append(start..<(start + size))
        start += size
    }
    return ranges
}

/// Widest cell wins, so twelve portrait frames land as 6 columns by 2 rows rather than 4 by 3.
/// Ties go to the tighter sheet: fewer rows, then fewer columns.
private func rank(_ grid: Grid) -> (Double, Int, Int) {
    (Double(grid.cell.width), -grid.rows, -grid.columns)
}

private func layout(columns: Int, count: Int, cellAspect: CGFloat, widestSource: CGFloat) -> Grid {
    let rows = (count + columns - 1) / columns
    let longEdge = CGFloat(Reader.longEdge)
    let byWidth = (longEdge - CGFloat(columns + 1) * Style.gutter) / CGFloat(columns)
    let byHeight = ((longEdge - CGFloat(rows + 1) * Style.gutter) / CGFloat(rows) - Style.labelHeight) * cellAspect
    let width = min(byWidth, byHeight, widestSource).rounded(.down)
    let height = (width / cellAspect).rounded(.down)
    return Grid(
        columns: columns,
        rows: rows,
        cell: CGSize(width: width, height: height),
        sheet: CGSize(
            width: CGFloat(columns) * width + CGFloat(columns + 1) * Style.gutter,
            height: CGFloat(rows) * (height + Style.labelHeight) + CGFloat(rows + 1) * Style.gutter
        )
    )
}

/// `widestSource` caps the cell: one wider than every image it holds would buy blank pixels at
/// full token price.
func grid(for count: Int, cellAspect: CGFloat, widestSource: CGFloat) -> Grid {
    var best = layout(columns: 1, count: count, cellAspect: cellAspect, widestSource: widestSource)
    for columns in stride(from: 2, through: count, by: 1) {
        let candidate = layout(columns: columns, count: count, cellAspect: cellAspect, widestSource: widestSource)
        if rank(candidate) > rank(best) {
            best = candidate
        }
    }
    return best
}

/// Aspect-fits `image` inside `area`, centred, never upscaled, on whole pixels so a letterbox
/// margin is an exact number of background rows.
func fittedRect(for image: CGImage, in area: CGRect) -> CGRect {
    let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height), 1)
    let width = (CGFloat(image.width) * scale).rounded()
    let height = (CGFloat(image.height) * scale).rounded()
    return CGRect(
        x: area.minX + ((area.width - width) / 2).rounded(.down),
        y: area.minY + ((area.height - height) / 2).rounded(.down),
        width: width,
        height: height
    )
}

func render(_ cells: ArraySlice<Cell>, in grid: Grid) -> CGImage {
    let context = CGContext(
        data: nil,
        width: Int(grid.sheet.width),
        height: Int(grid.sheet.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(Style.background)
    context.fill(CGRect(origin: .zero, size: grid.sheet))
    context.interpolationQuality = .high
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingMiddle
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: Style.labelFontSize, weight: .semibold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]

    for (index, cell) in cells.enumerated() {
        let column = index % grid.columns
        let row = index / grid.columns
        let x = Style.gutter + CGFloat(column) * (grid.cell.width + Style.gutter)
        let fromTop = Style.gutter + CGFloat(row) * (grid.cell.height + Style.labelHeight + Style.gutter)
        let area = CGRect(
            x: x,
            y: grid.sheet.height - fromTop - Style.labelHeight - grid.cell.height,
            width: grid.cell.width,
            height: grid.cell.height
        )
        context.draw(cell.image, in: fittedRect(for: cell.image, in: area))
        let strip = CGRect(x: x + 2, y: area.maxY + 5, width: grid.cell.width - 4, height: Style.labelHeight - 5)
        NSAttributedString(string: cell.label, attributes: attributes).draw(in: strip)
    }
    return context.makeImage()!
}

func load(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw Failure.unreadable(path: path)
    }
    return image
}

func url(forPage page: Int, of out: URL) -> URL {
    guard page > 1 else { return out }
    let stem = out.deletingPathExtension().lastPathComponent
    return out.deletingLastPathComponent().appendingPathComponent("\(stem)-\(page).png")
}

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw Failure.unwritable(path: url.path)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw Failure.unwritable(path: url.path)
    }
}

/// A rerun with fewer images must not leave an old page behind for a reader to mistake for current.
/// Bounded: only names this tool generates, and it stops at the first gap.
func removeStalePages(after lastPage: Int, of out: URL) {
    var page = lastPage + 1
    while true {
        let stale = url(forPage: page, of: out)
        guard FileManager.default.fileExists(atPath: stale.path) else { return }
        try? FileManager.default.removeItem(at: stale)
        page += 1
    }
}

func tokens(_ size: CGSize) -> Int {
    let patch = CGFloat(Reader.patch)
    return Int((size.width / patch).rounded(.up)) * Int((size.height / patch).rounded(.up))
}

func stem(of path: String) -> String {
    URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
}

func line(for page: URL, grid: Grid, cells: ArraySlice<Cell>) -> String {
    [
        page.path,
        "\(Int(grid.sheet.width))x\(Int(grid.sheet.height))",
        "\(cells.count) image\(cells.count == 1 ? "" : "s")",
        "about \(tokens(grid.sheet)) tokens",
        cells.map(\.label).joined(separator: "  ")
    ].joined(separator: "\t")
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 2, arguments[0].hasSuffix(".png") else { throw Failure.usage }
    let out = URL(fileURLWithPath: arguments[0])
    let paths = Array(arguments.dropFirst())
    let images = try paths.map(load)
    let cells = paths.enumerated().map { index, path in
        Cell(label: "\(index + 1). \(stem(of: path))", image: images[index])
    }
    let cellAspect = images.map { CGFloat($0.width) / CGFloat($0.height) }.min()!
    let widestSource = images.map { CGFloat($0.width) }.max()!

    let ranges = pages(of: cells.count)
    for (index, range) in ranges.enumerated() {
        let page = url(forPage: index + 1, of: out)
        let sheet = grid(for: range.count, cellAspect: cellAspect, widestSource: widestSource)
        try write(render(cells[range], in: sheet), to: page)
        print(line(for: page, grid: sheet, cells: cells[range]))
    }
    removeStalePages(after: ranges.count, of: out)
}

do {
    try run()
} catch let failure as Failure {
    FileHandle.standardError.write(Data((failure.message + "\n").utf8))
    exit(failure.exitCode)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(70)
}
