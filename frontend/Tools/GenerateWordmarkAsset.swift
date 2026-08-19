
import AppKit
import CoreText
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
enum GenerateWordmarkAsset {
    static func main() throws {
        try MainActor.assumeIsolated { try generate() }
    }
}

@MainActor
private func generate() throws {
    let faces = ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"]
    let fontURLs = faces.map { URL(fileURLWithPath: "Signu/Fonts/\($0).ttf") }
    for url in fontURLs where !FileManager.default.fileExists(atPath: url.path) {
        fatalError("missing font: \(url.path) — run from the frontend/ directory")
    }
    CTFontManagerRegisterFontURLs(fontURLs as CFArray, .process, false, nil)

    let outDir = URL(fileURLWithPath: "Signu/Assets.xcassets/Wordmark.imageset")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let renderer = ImageRenderer(content: SignuWordmark())
    renderer.isOpaque = false

    var logicalSize = CGSize.zero
    for scale in [1, 2, 3] {
        renderer.scale = CGFloat(scale)
        guard let image = renderer.cgImage else { fatalError("render failed at \(scale)x") }
        if scale == 1 { logicalSize = CGSize(width: image.width, height: image.height) }

        let name = scale == 1 ? "Wordmark.png" : "Wordmark@\(scale)x.png"
        let url = outDir.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("could not open \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    }

    let contents = """
    {
      "images" : [
        {
          "filename" : "Wordmark.png",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "filename" : "Wordmark@2x.png",
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "filename" : "Wordmark@3x.png",
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    try contents.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    print("Wordmark rendered at \(Int(logicalSize.width))×\(Int(logicalSize.height)) pt")
}
