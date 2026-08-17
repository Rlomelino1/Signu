import SwiftUI

/// Tier 1 and the cache of the logo sourcing contract (v12).
///
/// THE CHAIN
///
///  1. **Runtime fetch by domain**, from logo.dev, cached to disk for 30 days.
///  2. **Bundled assets** — deliberately unpopulated. "Don't build it until it
///     hurts": insurance against a logo.dev outage or an uncovered domain, added
///     only if tier 1 fails in practice.
///  3. **The monogram tile**, which needs no data and is what `ServiceAvatar`
///     already draws.
///
/// WHY IT FETCHES LOGOS THE USER HAS NO SUBSCRIPTION TO
///
/// Fetching only the domains a user is subscribed to would tell logo.dev the
/// user's subscription list, one request at a time — a financial-behaviour
/// fingerprint tied to an IP. So `prefetch` walks the WHOLE catalog: the request
/// set is identical for every install and independent of anyone's data. The cost
/// is roughly two megabytes once per TTL, which is nothing, and the property is
/// structural rather than a promise.
///
/// This is a mitigation and not anonymity: logo.dev still sees an IP fetching
/// logos and roughly when. Hiding that entirely means the bundled tier, which
/// trades away the rebrand freshness the tier order was inverted to get.
@MainActor
@Observable
final class LogoStore {

    /// Cached decoded images, keyed by domain. The disk copy behind it survives
    /// launches; this survives a scroll.
    private var images: [String: Image] = [:]
    private var missing: Set<String> = []
    private var inFlight: Set<String> = []
    private(set) var catalog: [BrandCatalogEntry] = []

    private let session: URLSession
    private let directory: URL

    /// 30 days, per the contract. Dropping to 7 is a one-line change if rebrand
    /// latency ever bothers; request volume is trivial either way.
    static let timeToLive: TimeInterval = 30 * 24 * 60 * 60

    init(session: URLSession = .shared) {
        self.session = session
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The logo for a displayed name, or nil for the monogram.
    ///
    /// Never fetches. Rendering a row must not start network work — the prefetch
    /// pass owns every request, which is also what keeps the request set
    /// independent of what the user is looking at. A cache miss here is simply a
    /// monogram, this launch.
    func image(forName name: String, kind: BrandKind) -> Image? {
        guard let domain = BrandCatalog.entry(for: name, in: catalog, kind: kind)?.domain
        else { return nil }
        return images[domain]
    }

    func adopt(catalog: [BrandCatalogEntry]) {
        self.catalog = catalog
    }

    /// Loads what disk already has, then fetches what is missing or stale.
    ///
    /// Called once per launch, off the critical path. Every domain in the catalog
    /// is considered — see the type comment for why that is the point rather than
    /// an oversight.
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

    // MARK: - Disk

    private func file(_ domain: String) -> URL {
        // The domain is the key, and a domain is already filesystem-safe once the
        // dots are gone. No hashing: a cache directory a human can read is a cache
        // directory a human can debug.
        directory.appendingPathComponent(domain.replacingOccurrences(of: ".", with: "_") + ".png")
    }

    private func loadFromDisk(_ domain: String) -> Image? {
        let url = file(domain)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        // Expiry is measured from when the file was written, not from a header:
        // the TTL is ours to state, and leaving it to the server's cache-control
        // would put the contract at the mercy of logo.dev's defaults.
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
                // A 404 is an ordinary answer — the catalog carries domains
                // logo.dev may not cover — so it is remembered, not retried this
                // launch, and never surfaced. A missing logo is a monogram.
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
