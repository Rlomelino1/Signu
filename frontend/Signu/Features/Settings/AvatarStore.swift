import SwiftUI

/// The profile picture, cached to disk, shared by every surface that renders it.
///
/// Modelled on `LogoStore` (v38) and for the same reasons, including the one that
/// matters most: **rendering never fetches.** A view asks for what is already
/// there and gets the monogram otherwise, so no scroll, no sheet and no re-render
/// can start network work.
///
/// WHERE THE TTL WENT
///
/// `LogoStore` expires disk copies after 30 days, because a merchant can rebrand
/// behind a URL that never changes. This cache needs no expiry at all: every
/// upload writes a NEW object path (Migration #11), so a changed picture is a
/// changed key and a stale hit is not possible. The old file is deleted when a new
/// path loads rather than left to age out.
@MainActor
@Observable
final class AvatarStore {

    /// The decoded picture and the path it came from. One entry, not a dictionary:
    /// there is exactly one profile.
    private(set) var image: Image?
    private var loadedPath: String?
    /// Paths that failed, so a missing object is not re-requested on every rebuild.
    /// Cleared by a path change, since that is a different object.
    private var failed: Set<String> = []

    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// What is already loaded, or nil for the monogram. Never fetches.
    func current(for path: String?) -> Image? {
        guard let path, path == loadedPath else { return nil }
        return image
    }

    /// Brings the cache in line with the profile: loads from disk, downloads if
    /// disk has nothing, and forgets the picture entirely when the path is nil.
    ///
    /// Idempotent, so the shell can call it on every appearance and refresh: a path
    /// already loaded returns immediately.
    func load(path: String?, using provider: SignuDataProviding) async {
        guard let path else {
            // Removed. Drop it from memory AND disk — a cache that outlives the
            // deletion would render a picture the user has just deleted.
            image = nil
            loadedPath = nil
            failed.removeAll()
            clearDisk()
            return
        }
        guard path != loadedPath else { return }
        guard !failed.contains(path) else { return }

        if let onDisk = UIImage(contentsOfFile: fileURL(for: path).path) {
            adopt(onDisk, path: path)
            return
        }

        do {
            let data = try await provider.avatarData(path: path)
            guard let decoded = UIImage(data: data) else {
                failed.insert(path)
                return
            }
            // Disk first, then memory: if the write fails the next launch simply
            // downloads again, which is the harmless direction.
            clearDisk()
            try? data.write(to: fileURL(for: path), options: .atomic)
            adopt(decoded, path: path)
        } catch {
            // A private bucket answers a deleted object with an error, and a row
            // can legitimately point at one for a moment. The monogram is the
            // honest fallback; it is not retried until the path changes.
            failed.insert(path)
        }
    }

    private func adopt(_ uiImage: UIImage, path: String) {
        image = Image(uiImage: uiImage)
        loadedPath = path
        failed.remove(path)
    }

    /// One file at a time. The path contains a `/` (`<uid>/<epoch>.jpg`), which
    /// cannot appear in a file name, so it is flattened rather than nested — a
    /// directory per user would be a directory that is never cleaned up.
    private func fileURL(for path: String) -> URL {
        directory.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }

    private func clearDisk() {
        guard let existing = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in existing { try? FileManager.default.removeItem(at: file) }
    }
}

/// The profile picture where there is one, the monogram where there is not.
///
/// A single view so the fallback is identical everywhere — Home's header, the
/// Settings row and the edit sheet all had their own ink circle before this, and
/// three copies of a fallback is three chances to disagree about it.
struct ProfileAvatar: View {
    let path: String?
    let initial: String
    var size: CGFloat = 44

    @Environment(AvatarStore.self) private var store: AvatarStore?

    var body: some View {
        Group {
            if let image = store?.current(for: path) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(SignuColor.ink)
                    .overlay {
                        Text(initial)
                            .font(SignuFont.font(size * 0.41, .semibold))
                            .foregroundStyle(SignuColor.onInk)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
