// Renders `SignuWordmark` to the Wordmark image set used by
// LaunchScreen.storyboard.
//
// Why an image at all: a launch storyboard is rejected by ibtool if it
// contains user-defined runtime attributes, so the wordmark's 18pt rounded
// tile cannot be drawn with a plain UIView — `layer.cornerRadius` is exactly
// what's disallowed. Rendering the real SwiftUI view instead keeps the launch
// image and `SplashView` identical by construction rather than by eyeballing
// two implementations.
//
// Re-run after any change to SignuWordmark, SignuColor, or the Inter faces:
//
//     cd frontend && ./Tools/generate-wordmark-asset.sh
//
// Not part of the app target (Tools/ sits outside the synchronized Signu/
// folder), so it never ships.

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
    // Inter is bundled, not installed — register it for this process so
    // Font.custom resolves the same faces the app uses.
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

    // The storyboard pins the image view to this size, so print it: a change
    // here means the storyboard's width/height constraints need updating.
    print("Wordmark rendered at \(Int(logicalSize.width))×\(Int(logicalSize.height)) pt")
}
