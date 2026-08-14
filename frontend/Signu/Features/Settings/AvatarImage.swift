import UIKit

/// Turning whatever the photo picker hands over into the one thing the avatars
/// bucket accepts: a small, square, sRGB JPEG.
///
/// A separate type, and not a method on the view, because every rule here has a
/// reason that outlives the screen that calls it — and because "the upload is
/// small and square" is testable, while a photo picker is not.
///
/// The bucket allows exactly `image/jpeg` (Migration #11), so this is not a
/// convenience: an unconverted HEIC from the camera is rejected by storage, and
/// the failure would land after the user picked a photo and waited.
enum AvatarImage {

    /// 512pt, which is 1024px on a 2x screen and 1536 on 3x. The largest place a
    /// profile picture renders in this app is 46pt, so this is already four times
    /// what any current screen needs — chosen for the screens that do not exist yet
    /// rather than the ones that do, since re-uploading everyone's photo later is
    /// not a migration anyone wants to write.
    static let side: CGFloat = 512

    /// 0.8 is the usual knee: visually indistinguishable from 1.0 at this size,
    /// roughly a third of the bytes. A 512px face lands at 50-150 KB, against the
    /// bucket's 2 MiB ceiling.
    static let quality: CGFloat = 0.8

    /// Square, downscaled, JPEG. Nil only if the image cannot be encoded at all,
    /// which for a UIImage from the picker means something is wrong with the source
    /// rather than with the arguments.
    ///
    /// **Cropped to a centred square rather than letterboxed**: every avatar
    /// surface in this app is a circle, so padding would render as bars inside the
    /// circle. Cropping loses edges the circle was going to clip anyway.
    static func jpeg(from image: UIImage) -> Data? {
        let squared = centreCropped(image)
        let format = UIGraphicsImageRendererFormat.default()
        // The picker can hand over P3 or HDR content. sRGB because the icon work
        // (v37) already learned that a colour space assumed rather than embedded
        // is a difference that shows up somewhere else, and because the target is
        // a JPEG that everything must be able to read.
        format.preferredRange = .standard
        // 1.0: `side` is being treated as pixels here, not points. A 3x scale would
        // triple the upload for no visible gain at 46pt.
        format.scale = 1

        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { _ in
            squared.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// The largest centred square inside the image, in its own orientation.
    ///
    /// Goes through `cgImage` so the crop is in pixels, then hands the orientation
    /// back to the result: cropping a `UIImage` while ignoring `imageOrientation`
    /// is how a portrait photo comes out sideways, and the picker returns
    /// orientation metadata rather than rotated pixels.
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
