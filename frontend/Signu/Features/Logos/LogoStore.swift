import SwiftUI

@MainActor
@Observable
final class LogoStore {

    private var images: [String: Image] = [:]
    private var missing: Set<String> = []
    private var inFlight: Set<String> = []
    private(set) var catalog: [BrandCatalogEntry] = []

    private let session: URLSession
    private let directory: URL

    static let timeToLive: TimeInterval = 30 * 24 * 60 * 60

    init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(forName name: String, kind: BrandKind) -> Image? {
        guard let domain = BrandCatalog.entry(for: name, in: catalog, kind: kind)?.domain
        else { return nil }
        return images[domain]
    }

    func adopt(catalog: [BrandCatalogEntry]) {
        self.catalog = catalog
    }

    func prefetch() async {
        guard SupabaseConfig.logoDevKey.isEmpty == false else { return }
        for domain in BrandCatalog.allDomains(in: catalog) {
            if images[domain] != nil || inFlight.contains(domain) { continue }
            if let cached = loadFromDisk(domain) {
                images[domain] = cached
                continue
            }
            inFlight.insert(domain)
            await fetch(domain)
            inFlight.remove(domain)
        }
    }


    private func file(_ domain: String) -> URL {
        directory.appendingPathComponent(domain.replacingOccurrences(of: ".", with: "_") + ".png")
    }

    private func loadFromDisk(_ domain: String) -> Image? {
        let url = file(domain)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        guard Date().timeIntervalSince(modified) < Self.timeToLive else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard let data = try? Data(contentsOf: url), let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
    }

    private func fetch(_ domain: String) async {
        guard var components = URLComponents(string: "https://img.logo.dev/\(domain)") else { return }
        components.queryItems = [
            URLQueryItem(name: "token", value: SupabaseConfig.logoDevKey),
            URLQueryItem(name: "size", value: "128"),
            URLQueryItem(name: "format", value: "png"),
        ]
        guard let url = components.url else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let ui = UIImage(data: data) else {
                missing.insert(domain)
                return
            }
            try? data.write(to: file(domain))
            images[domain] = Image(uiImage: ui)
        } catch {
            missing.insert(domain)
        }
    }
}
