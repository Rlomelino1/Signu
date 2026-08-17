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
                             category: "Fitness", subscriptionOnly: true, patterns: ["local gym"]),
        // Migration #13, verbatim. subscriptionOnly is FALSE here where the rest are
        // true, because Steam mostly sells one-off games — see the migration header.
        MerchantCatalogEntry(id: UUID(), serviceName: "Steam", domain: "steampowered.com",
                             category: "Games", subscriptionOnly: false,
                             patterns: ["steam", "valve", "trueline valve"])
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
        #expect(domains == [
            "amazon.com", "amazon.com.br", "estadao.com.br", "netflix.com", "steampowered.com",
        ])
    }

    @Test("a merchant with no domain is simply not fetched")
    func nilDomainsAreSkipped() {
        // And renders the monogram, which is tier 3 of the chain rather than a
        // failure: nothing to fetch, nothing to leak.
        #expect(!MerchantCatalog.allDomains(in: catalog).contains(""))
        // Six entries, five domains: the gym's is nil.
        #expect(MerchantCatalog.allDomains(in: catalog).count == 5)
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

    // MARK: - The descriptor a bank actually sends (v56)

    @Test("Steam is found through Valve's billing descriptor, not its name")
    func steamViaTruelineValve() throws {
        // The real string on the statement, and the first subscription this app ever
        // detected: 'TRUELINE VALVE CORPORATION'. A name-only entry cannot match it —
        // 'steam' is not a substring — which is what the patterns column is for.
        let entry = try #require(
            MerchantCatalog.entry(for: "TRUELINE VALVE CORPORATION", in: catalog)
        )
        #expect(entry.serviceName == "Steam")
        #expect(entry.domain == "steampowered.com")
    }

    @Test("the plain name and a lowercase descriptor both resolve")
    func steamByNameAndCase() throws {
        for name in ["Steam", "steam", "STEAM WALLET", "valve corp"] {
            let entry = try #require(MerchantCatalog.entry(for: name, in: catalog), "\(name)")
            #expect(entry.serviceName == "Steam")
        }
    }

    @Test("Steam is not marked subscription-only, unlike most of the catalog")
    func steamIsNotSubscriptionOnly() throws {
        // R4's trigger. True here would eventually promote every game bought to a
        // subscription, since subscription_only says "a charge from this merchant is
        // ALWAYS a subscription" — a claim about the merchant, not about one charge.
        let steam = try #require(MerchantCatalog.entry(for: "Steam", in: catalog))
        #expect(steam.subscriptionOnly == false)
        let netflix = try #require(MerchantCatalog.entry(for: "Netflix", in: catalog))
        #expect(netflix.subscriptionOnly)
    }
}
