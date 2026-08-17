import Foundation

/// What a brand IS, and therefore which names it may be matched against (v58).
///
/// The distinction is not cosmetic. `patterns` are matched against descriptors, and
/// 'nu pagamentos' appears on Brazilian statements as the ACQUIRER — so an unscoped
/// lookup would hand a Nubank-acquired subscription the bank's logo. Scoping by kind
/// removes that by construction rather than by writing careful patterns.
enum BrandKind: String, Sendable {
    /// Something the user subscribes to. Matched against subscription descriptors.
    case service
    /// A bank. Matched against the label the app derives for a connection (v43).
    case institution
}

/// One row of BRAND_CATALOG — shared reference data, identical for every user.
///
/// `domain` is nullable by design (v12): a merchant with no known domain falls
/// through to the monogram, and that is a complete answer rather than a gap.
struct BrandCatalogEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    var brandName: String
    var domain: String?
    var category: String?
    /// R4's trigger — a charge from this merchant is always a subscription.
    /// Carried now, unused until R4 is built, so that rule needs no migration.
    /// Meaningless for an `institution`: nobody subscribes to their bank, and the
    /// column is not nullable, so those rows carry false rather than a claim.
    var subscriptionOnly: Bool
    /// Whether this row describes a service or a bank. Decides which names it can
    /// match — see `BrandKind`.
    var kind: BrandKind
    /// Lowercase fragments matched against a merchant descriptor.
    var patterns: [String]
}

/// Resolving a service name to a catalog entry.
///
/// Pure and separate from the store that fetches images, because this is the part
/// with rules in it: matching is by canonical name first and pattern second, and
/// "no match" has to be an ordinary answer rather than an error.
enum BrandCatalog {

    /// The entry a displayed name belongs to, or nil.
    ///
    /// Name first, patterns second. A subscription's `service_name` is what the
    /// engine seeded from the descriptor, so an exact (case- and
    /// accent-insensitive) hit is the strongest signal available; patterns catch
    /// the descriptor variants an acquirer introduces.
    ///
    /// **Known limitation, stated rather than hidden**: a renamed subscription is
    /// displayed by its nickname, and a nickname does not match the catalog. The
    /// logo falls back to the monogram, which is wrong-looking but not
    /// wrong-saying. Fixing it means carrying the engine's name alongside the
    /// display name to every avatar, which is a wide change for a decorative
    /// gain.
    /// - Parameter kind: the only rows considered. Required rather than defaulted:
    ///   the caller always knows whether it is labelling a subscription or a bank, and
    ///   a default would make the unscoped behaviour — the one this exists to prevent —
    ///   the easiest thing to write.
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
        // Longest pattern first, so "amazon prime" wins over "amazon" when both
        // are present. Without the ordering the answer would depend on row order,
        // which is a database detail and not a rule.
        return catalog
            .flatMap { entry in entry.patterns.map { (pattern: normalise($0), entry: entry) } }
            .filter { !$0.pattern.isEmpty && needle.contains($0.pattern) }
            .max { $0.pattern.count < $1.pattern.count }?
            .entry
    }

    /// Every domain worth fetching, deduplicated — **both kinds**, deliberately.
    ///
    /// The privacy property below depends on the fetch set being the whole catalog. If
    /// this ever filtered by kind, the request set would start describing which
    /// surfaces the user is looking at, which is a smaller version of exactly the leak
    /// the padding prevents.
    ///
    /// THE PRIVACY-CRITICAL FUNCTION. The client fetches all of these regardless
    /// of what the user is subscribed to, so the request set is constant and says
    /// nothing about anybody. Taking the user's subscriptions as an input here —
    /// the obvious optimisation — would hand the third party the subscription
    /// list one request at a time, which is exactly what the padding exists to
    /// prevent. There is deliberately no overload that accepts them.
    static func allDomains(in catalog: [BrandCatalogEntry]) -> [String] {
        Array(Set(catalog.compactMap(\.domain))).sorted()
    }

    /// Case-, accent- and punctuation-insensitive. "iCloud+" and "icloud" are the
    /// same merchant; so are "Estadão" and "estadao".
    static func normalise(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
