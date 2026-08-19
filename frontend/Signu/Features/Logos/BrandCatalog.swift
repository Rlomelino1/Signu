import Foundation

enum BrandKind: String, Sendable {
    case service
    case institution
}

struct BrandCatalogEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    var brandName: String
    var domain: String?
    var category: String?
    var subscriptionOnly: Bool
    var kind: BrandKind
    var patterns: [String]
}

enum BrandCatalog {

    static func entry(
        for name: String,
        in catalog: [BrandCatalogEntry],
        kind: BrandKind
    ) -> BrandCatalogEntry? {
        let needle = normalise(name)
        guard !needle.isEmpty else { return nil }
        let catalog = catalog.filter { $0.kind == kind }

        if let exact = catalog.first(where: { normalise($0.brandName) == needle }) {
            return exact
        }
        return catalog
            .flatMap { entry in entry.patterns.map { (pattern: normalise($0), entry: entry) } }
            .filter { !$0.pattern.isEmpty && needle.contains($0.pattern) }
            .max { $0.pattern.count < $1.pattern.count }?
            .entry
    }

    static func allDomains(in catalog: [BrandCatalogEntry]) -> [String] {
        Array(Set(catalog.compactMap(\.domain))).sorted()
    }

    static func normalise(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
