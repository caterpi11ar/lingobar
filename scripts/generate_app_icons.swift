import AppKit
import Foundation

struct IconSpec {
    let size: Int
    let scale: Int
    let idiom: String
    let filename: String

    var pixelSize: Int { size * scale }
}

enum IconGeneratorError: Error, LocalizedError {
    case invalidArguments
    case failedToLoadSource(String)
    case failedToRender(Int)
    case failedToEncode(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Usage: generate_app_icons.swift <input-svg> <output-appiconset>"
        case let .failedToLoadSource(path):
            return "Failed to load icon source at \(path)"
        case let .failedToRender(size):
            return "Failed to render icon at \(size)x\(size)"
        case let .failedToEncode(path):
            return "Failed to write PNG to \(path)"
        }
    }
}

@main
struct IconGenerator {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            throw IconGeneratorError.invalidArguments
        }

        let inputURL = URL(fileURLWithPath: arguments[1])
        let outputURL = URL(fileURLWithPath: arguments[2], isDirectory: true)

        guard let sourceImage = NSImage(contentsOf: inputURL) else {
            throw IconGeneratorError.failedToLoadSource(inputURL.path)
        }

        let specs: [IconSpec] = [
            .init(size: 16, scale: 1, idiom: "mac", filename: "icon_16x16.png"),
            .init(size: 16, scale: 2, idiom: "mac", filename: "icon_16x16@2x.png"),
            .init(size: 32, scale: 1, idiom: "mac", filename: "icon_32x32.png"),
            .init(size: 32, scale: 2, idiom: "mac", filename: "icon_32x32@2x.png"),
            .init(size: 128, scale: 1, idiom: "mac", filename: "icon_128x128.png"),
            .init(size: 128, scale: 2, idiom: "mac", filename: "icon_128x128@2x.png"),
            .init(size: 256, scale: 1, idiom: "mac", filename: "icon_256x256.png"),
            .init(size: 256, scale: 2, idiom: "mac", filename: "icon_256x256@2x.png"),
            .init(size: 512, scale: 1, idiom: "mac", filename: "icon_512x512.png"),
            .init(size: 512, scale: 2, idiom: "mac", filename: "icon_512x512@2x.png"),
        ]

        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        var contentsEntries: [[String: String]] = []

        for spec in specs {
            let pngURL = outputURL.appendingPathComponent(spec.filename)
            try renderPNG(from: sourceImage, pixelSize: spec.pixelSize, to: pngURL)
            contentsEntries.append([
                "idiom": spec.idiom,
                "size": "\(spec.size)x\(spec.size)",
                "scale": "\(spec.scale)x",
                "filename": spec.filename,
            ])
        }

        let contentsObject: [String: Any] = [
            "images": contentsEntries,
            "info": [
                "author": "xcode",
                "version": 1,
            ],
        ]

        let contentsData = try JSONSerialization.data(withJSONObject: contentsObject, options: [.prettyPrinted, .sortedKeys])
        try contentsData.write(to: outputURL.appendingPathComponent("Contents.json"))
    }
}

@MainActor
private func renderPNG(from sourceImage: NSImage, pixelSize: Int, to url: URL) throws {
    guard
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        throw IconGeneratorError.failedToRender(pixelSize)
    }

    representation.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        throw IconGeneratorError.failedToRender(pixelSize)
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()

    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = representation.representation(using: .png, properties: [:]) else {
        throw IconGeneratorError.failedToEncode(url.path)
    }
    try pngData.write(to: url)
}
