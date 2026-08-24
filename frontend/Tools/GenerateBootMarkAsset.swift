
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the resting Signu mark into `BootMark.imageset` for the launch
/// storyboard, which cannot draw it: ibtool rejects the user-defined runtime
/// attributes a stroked arc would need, the same reason the wordmark is an
/// image. Re-run this if `SignuArcsMark` changes, and update the storyboard's
/// size constraints if the printed size changes.
///
/// No fonts are registered because the mark is pure geometry.
@main
enum GenerateBootMarkAsset {
    static func main() throws {
        try MainActor.assumeIsolated { try generate() }
    }
}

@MainActor
private func generate() throws {
    let outDir = URL(fileURLWithPath: "Signu/Assets.xcassets/BootMark.imageset")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let renderer = ImageRenderer(content: SignuArcsMark())
    renderer.isOpaque = false

    var logicalSize = CGSize.zero
    for scale in [1, 2, 3] {
        renderer.scale = CGFloat(scale)
        guard let image = renderer.cgImage else { fatalError("render failed at \(scale)x") }
        if scale == 1 { logicalSize = CGSize(width: image.width, height: image.height) }

        let name = scale == 1 ? "BootMark.png" : "BootMark@\(scale)x.png"
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
          "filename" : "BootMark.png",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "filename" : "BootMark@2x.png",
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "filename" : "BootMark@3x.png",
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

    print("BootMark rendered at \(Int(logicalSize.width))×\(Int(logicalSize.height)) pt")
}
