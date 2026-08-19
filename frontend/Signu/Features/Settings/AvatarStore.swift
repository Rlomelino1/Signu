import SwiftUI

@MainActor
@Observable
final class AvatarStore {

    private(set) var image: Image?
    private var loadedPath: String?

    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func current(for path: String?) -> Image? {
        guard let path, path == loadedPath else { return nil }
        return image
    }

    func load(path: String?, using provider: SignuDataProviding) async {
        guard let path else {
            image = nil
            loadedPath = nil
            clearDisk()
            return
        }
        guard path != loadedPath else { return }

        if let onDisk = UIImage(contentsOfFile: fileURL(for: path).path) {
            adopt(onDisk, path: path)
            return
        }

        do {
            let data = try await provider.avatarData(path: path)
            guard let decoded = UIImage(data: data) else { return }
            clearDisk()
            try? data.write(to: fileURL(for: path), options: .atomic)
            adopt(decoded, path: path)
        } catch {
        }
    }

    private func adopt(_ uiImage: UIImage, path: String) {
        image = Image(uiImage: uiImage)
        loadedPath = path
    }

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
