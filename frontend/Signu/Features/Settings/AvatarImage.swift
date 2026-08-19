import UIKit

enum AvatarImage {

    static let side: CGFloat = 512

    static let quality: CGFloat = 0.8

    static func jpeg(from image: UIImage) -> Data? {
        let squared = centreCropped(image)
        let format = UIGraphicsImageRendererFormat.default()
        format.preferredRange = .standard
        format.scale = 1

        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { _ in
            squared.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    static func centreCropped(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)
        guard width != height else { return image }

        let rect = CGRect(
            x: ((width - side) / 2).rounded(.down),
            y: ((height - side) / 2).rounded(.down),
            width: side,
            height: side
        )
        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
