import Testing
import UIKit
@testable import Signu


@Suite("Avatar encoding (v47)")
struct AvatarImageTests {

    private func image(width: CGFloat, height: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test("the upload is a JPEG, whatever went in")
    func encodesJPEG() throws {
        let data = try #require(AvatarImage.jpeg(from: image(width: 400, height: 400)))
        #expect(data.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test("the upload is square at the declared side, whatever the aspect ratio")
    func squaresAndDownscales() throws {
        for (width, height) in [(4032.0, 3024.0), (1080.0, 1920.0), (600.0, 600.0)] {
            let data = try #require(AvatarImage.jpeg(from: image(width: width, height: height)))
            let decoded = try #require(UIImage(data: data))
            #expect(decoded.size.width == AvatarImage.side)
            #expect(decoded.size.height == AvatarImage.side)
        }
    }

    @Test("a 12-megapixel photo lands far under the bucket's ceiling")
    func staysSmall() throws {
        let data = try #require(AvatarImage.jpeg(from: image(width: 4032, height: 3024)))
        #expect(data.count < 2 * 1024 * 1024)
    }

    @Test("the crop is centred, not a stretch")
    func cropsRatherThanStretches() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 400))
        let source = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 100, width: 200, height: 300))
        }

        let cropped = AvatarImage.centreCropped(source)
        #expect(cropped.size.width == cropped.size.height)
        #expect(cropped.size.width == 200)

        let topLeft = try #require(colour(of: cropped, atX: 4, y: 4))
        #expect(topLeft.red < 0.30, "the cropped image still starts inside the red band")
        #expect(topLeft.blue > 0.60, "the crop should begin in the blue region")
    }

    @Test("an already-square image is returned untouched by the crop")
    func squareIsUntouched() {
        let square = image(width: 300, height: 300)
        let cropped = AvatarImage.centreCropped(square)
        #expect(cropped.size == square.size)
    }

    private func colour(
        of image: UIImage, atX x: Int, y: Int
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: CGFloat(-x), y: CGFloat(-y))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}
