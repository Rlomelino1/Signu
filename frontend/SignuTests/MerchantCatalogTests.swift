import Testing
import Foundation
@testable import Signu

// Resolving a merchant to its catalog entry, and the privacy property the logo
// prefetch rests on (v38).

@Suite("Merchant catalog")
@MainActor
struct MerchantCatalogTests {

    private let catalog: [MerchantCatalogEntry] = [
        MerchantCatalogEntry(id: UUID(), serviceName: "Netflix", domain: "netflix.com",
                             category: "Streaming", subscriptionOnly: true, patterns: ["netflix"]),
        MerchantCatalogEntry(id: UUID(), serviceName: "Amazon Prime", domain: "amazon.com.br",
                             category: "Shopping", subscriptionOnly: true, patterns: ["amazon prime"]),
        MerchantCatalogEntry(id: UUID(), serviceName: "Kindle Unlimited", domain: "amazon.com",
                             category: "Books", subscriptionOnly: true, patterns: ["amazon", "kindle unlimited"]),
        MerchantCatalogEntry(id: UUID(), serviceName: "Estadão", domain: "estadao.com.br",
                             category: "News", subscriptionOnly: true, patterns: ["estadao"]),
        MerchantCatalogEntry(id: UUID(), serviceName: "Some Local Gym", domain: nil,
                             category: "Fitness", subscriptionOnly: true, patterns: ["local gym"])
    ]

    // MARK: - Matching

    @Test("an exact name wins")
    func exactName() {
        #expect(MerchantCatalog.entry(for: "Netflix", in: catalog)?.domain == "netflix.com")
    }

    @Test("case and accents do not matter")
    func caseAndAccents() {
        // "Estadão" arrives from the engine with its diacritic and from a
        // descriptor without one; both are the same merchant.
        #expect(MerchantCatalog.entry(for: "estadao", in: catalog)?.serviceName == "Estadão")
        #expect(MerchantCatalog.entry(for: "ESTADÃO", in: catalog)?.serviceName == "Estadão")
    }

    @Test("a pattern matches when the name does not")
    func patternFallback() {
        #expect(MerchantCatalog.entry(for: "Netflix.com Brasil", in: catalog)?.domain == "netflix.com")
    }

    @Test("the longest pattern wins")
    func longestPatternWins() {
        // "Amazon Prime" contains "amazon" too. Without the ordering the answer
        // would depend on row order, which is a database detail rather than a
        // rule — and the wrong entry brings the wrong logo AND the wrong category.
        #expect(MerchantCatalog.entry(for: "Amazon Prime BR", in: catalog)?.serviceName == "Amazon Prime")
        #expect(MerchantCatalog.entry(for: "Amazon Services", in: catalog)?.serviceName == "Kindle Unlimited")
    }

    @Test("no match is an ordinary answer")
    func noMatch() {
        #expect(MerchantCatalog.entry(for: "Padaria do Zé", in: catalog) == nil)
        #expect(MerchantCatalog.entry(for: "", in: catalog) == nil)
        #expect(MerchantCatalog.entry(for: "   ", in: catalog) == nil)
    }

    @Test("a nickname does not match, and that is the known limitation")
    func nicknamesDoNotMatch() {
        // Renaming a subscription costs it its logo, because the avatar receives
        // the display name. Recorded as a test rather than a comment so the day
        // it changes, something says so.
        #expect(MerchantCatalog.entry(for: "Movies (mine)", in: catalog) == nil)
    }

    // MARK: - The privacy property

    @Test("every domain is fetched, including merchants nobody is subscribed to")
    func allDomainsIsUserIndependent() {
        // THE point of the design. The fetch set is the catalog, so it is
        // identical for every install and discloses nothing about anyone. If this
        // ever narrows to "the user's merchants", the third party learns the
        // subscription list one request at a time.
        let domains = MerchantCatalog.allDomains(in: catalog)
        #expect(domains == ["amazon.com", "amazon.com.br", "estadao.com.br", "netflix.com"])
    }

    @Test("a merchant with no domain is simply not fetched")
    func nilDomainsAreSkipped() {
        // And renders the monogram, which is tier 3 of the chain rather than a
        // failure: nothing to fetch, nothing to leak.
        #expect(!MerchantCatalog.allDomains(in: catalog).contains(""))
        #expect(MerchantCatalog.allDomains(in: catalog).count == 4)
    }

    @Test("the mock catalog lists services the fixtures do not subscribe to")
    func mockCatalogIsNotDerivedFromTheUser() async throws {
        // The same constraint the migration's seed is under, checked where it can
        // be: a catalog assembled from the user's own merchants would make
        // "fetch everything" leak precisely the list it exists to hide.
        let p = MockDataProvider()
        let entries = try await p.merchantCatalog()
        let subscribed = Set(try await p.subscriptions().map { MerchantCatalog.normalise($0.serviceName) })
        let unsubscribed = entries.filter { !subscribed.contains(MerchantCatalog.normalise($0.serviceName)) }
        #expect(!unsubscribed.isEmpty, "the catalog must describe the world, not the account")
    }
}
