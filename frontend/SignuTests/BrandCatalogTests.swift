import Testing
import Foundation
@testable import Signu

// Resolving a merchant to its catalog entry, and the privacy property the logo
// prefetch rests on (v38).

@Suite("Brand catalog")
@MainActor
struct BrandCatalogTests {

    private let catalog: [BrandCatalogEntry] = [
        BrandCatalogEntry(id: UUID(), brandName: "Netflix", domain: "netflix.com",
                             category: "Streaming", subscriptionOnly: true, kind: .service, patterns: ["netflix"]),
        BrandCatalogEntry(id: UUID(), brandName: "Amazon Prime", domain: "amazon.com.br",
                             category: "Shopping", subscriptionOnly: true, kind: .service, patterns: ["amazon prime"]),
        BrandCatalogEntry(id: UUID(), brandName: "Kindle Unlimited", domain: "amazon.com",
                             category: "Books", subscriptionOnly: true, kind: .service, patterns: ["amazon", "kindle unlimited"]),
        BrandCatalogEntry(id: UUID(), brandName: "Estadão", domain: "estadao.com.br",
                             category: "News", subscriptionOnly: true, kind: .service, patterns: ["estadao"]),
        BrandCatalogEntry(id: UUID(), brandName: "Some Local Gym", domain: nil,
                             category: "Fitness", subscriptionOnly: true, kind: .service, patterns: ["local gym"]),
        // Migration #13, verbatim. subscriptionOnly is FALSE here where the rest are
        // true, because Steam mostly sells one-off games — see the migration header.
        // Institutions (v58), as Migration #14 seeds them.
        BrandCatalogEntry(id: UUID(), brandName: "Nubank", domain: "nubank.com.br",
                             category: "Bank", subscriptionOnly: false, kind: .institution,
                             patterns: ["nubank", "nu pagamentos", "nu bank"]),
        BrandCatalogEntry(id: UUID(), brandName: "C6 Bank", domain: "c6bank.com.br",
                             category: "Bank", subscriptionOnly: false, kind: .institution,
                             patterns: ["c6 bank", "banco c6", "c6 standard"]),
        BrandCatalogEntry(id: UUID(), brandName: "Steam", domain: "steampowered.com",
                             category: "Games", subscriptionOnly: false, kind: .service,
                             patterns: ["steam", "valve", "trueline valve"])
    ]

    // MARK: - Matching

    @Test("an exact name wins")
    func exactName() {
        #expect(BrandCatalog.entry(for: "Netflix", in: catalog, kind: .service)?.domain == "netflix.com")
    }

    @Test("case and accents do not matter")
    func caseAndAccents() {
        // "Estadão" arrives from the engine with its diacritic and from a
        // descriptor without one; both are the same merchant.
        #expect(BrandCatalog.entry(for: "estadao", in: catalog, kind: .service)?.brandName == "Estadão")
        #expect(BrandCatalog.entry(for: "ESTADÃO", in: catalog, kind: .service)?.brandName == "Estadão")
    }

    @Test("a pattern matches when the name does not")
    func patternFallback() {
        #expect(BrandCatalog.entry(for: "Netflix.com Brasil", in: catalog, kind: .service)?.domain == "netflix.com")
    }

    @Test("the longest pattern wins")
    func longestPatternWins() {
        // "Amazon Prime" contains "amazon" too. Without the ordering the answer
        // would depend on row order, which is a database detail rather than a
        // rule — and the wrong entry brings the wrong logo AND the wrong category.
        #expect(BrandCatalog.entry(for: "Amazon Prime BR", in: catalog, kind: .service)?.brandName == "Amazon Prime")
        #expect(BrandCatalog.entry(for: "Amazon Services", in: catalog, kind: .service)?.brandName == "Kindle Unlimited")
    }

    @Test("no match is an ordinary answer")
    func noMatch() {
        #expect(BrandCatalog.entry(for: "Padaria do Zé", in: catalog, kind: .service) == nil)
        #expect(BrandCatalog.entry(for: "", in: catalog, kind: .service) == nil)
        #expect(BrandCatalog.entry(for: "   ", in: catalog, kind: .service) == nil)
    }

    @Test("a nickname does not match, and that is the known limitation")
    func nicknamesDoNotMatch() {
        // Renaming a subscription costs it its logo, because the avatar receives
        // the display name. Recorded as a test rather than a comment so the day
        // it changes, something says so.
        #expect(BrandCatalog.entry(for: "Movies (mine)", in: catalog, kind: .service) == nil)
    }

    // MARK: - The privacy property

    @Test("every domain is fetched, including merchants nobody is subscribed to")
    func allDomainsIsUserIndependent() {
        // THE point of the design. The fetch set is the catalog, so it is
        // identical for every install and discloses nothing about anyone. If this
        // ever narrows to "the user's merchants", the third party learns the
        // subscription list one request at a time.
        let domains = BrandCatalog.allDomains(in: catalog)
        // Institutions included on purpose: the fetch set is the WHOLE catalog, both
        // kinds, so it stays independent of which surface the user is looking at.
        #expect(domains == [
            "amazon.com", "amazon.com.br", "c6bank.com.br", "estadao.com.br",
            "netflix.com", "nubank.com.br", "steampowered.com",
        ])
    }

    @Test("a merchant with no domain is simply not fetched")
    func nilDomainsAreSkipped() {
        // And renders the monogram, which is tier 3 of the chain rather than a
        // failure: nothing to fetch, nothing to leak.
        #expect(!BrandCatalog.allDomains(in: catalog).contains(""))
        // Eight entries, seven domains: the gym's is nil.
        #expect(BrandCatalog.allDomains(in: catalog).count == 7)
    }

    @Test("the mock catalog lists services the fixtures do not subscribe to")
    func mockCatalogIsNotDerivedFromTheUser() async throws {
        // The same constraint the migration's seed is under, checked where it can
        // be: a catalog assembled from the user's own merchants would make
        // "fetch everything" leak precisely the list it exists to hide.
        let p = MockDataProvider()
        let entries = try await p.brandCatalog()
        let subscribed = Set(try await p.subscriptions().map { BrandCatalog.normalise($0.serviceName) })
        let unsubscribed = entries.filter { !subscribed.contains(BrandCatalog.normalise($0.brandName)) }
        #expect(!unsubscribed.isEmpty, "the catalog must describe the world, not the account")
    }

    // MARK: - The descriptor a bank actually sends (v56)

    @Test("Steam is found through Valve's billing descriptor, not its name")
    func steamViaTruelineValve() throws {
        // The real string on the statement, and the first subscription this app ever
        // detected: 'TRUELINE VALVE CORPORATION'. A name-only entry cannot match it —
        // 'steam' is not a substring — which is what the patterns column is for.
        let entry = try #require(
            BrandCatalog.entry(for: "TRUELINE VALVE CORPORATION", in: catalog, kind: .service)
        )
        #expect(entry.brandName == "Steam")
        #expect(entry.domain == "steampowered.com")
    }

    @Test("the plain name and a lowercase descriptor both resolve")
    func steamByNameAndCase() throws {
        for name in ["Steam", "steam", "STEAM WALLET", "valve corp"] {
            let entry = try #require(BrandCatalog.entry(for: name, in: catalog, kind: .service), "\(name)")
            #expect(entry.brandName == "Steam")
        }
    }

    @Test("Steam is not marked subscription-only, unlike most of the catalog")
    func steamIsNotSubscriptionOnly() throws {
        // R4's trigger. True here would eventually promote every game bought to a
        // subscription, since subscription_only says "a charge from this merchant is
        // ALWAYS a subscription" — a claim about the merchant, not about one charge.
        let steam = try #require(BrandCatalog.entry(for: "Steam", in: catalog, kind: .service))
        #expect(steam.subscriptionOnly == false)
        let netflix = try #require(BrandCatalog.entry(for: "Netflix", in: catalog, kind: .service))
        #expect(netflix.subscriptionOnly)
    }

    // MARK: - The scoping the kind column exists for (v58)

    @Test("a bank is found through the label the app derives for it")
    func institutionsResolve() throws {
        // Production's derived labels, verbatim: BankLabel turns the connector's
        // "MeuPluggy" into the checking account's own name (v43).
        let nubank = try #require(
            BrandCatalog.entry(for: "Nu Pagamentos S.A.", in: catalog, kind: .institution)
        )
        #expect(nubank.domain == "nubank.com.br")
        let c6 = try #require(
            BrandCatalog.entry(for: "C6 BANK", in: catalog, kind: .institution)
        )
        #expect(c6.domain == "c6bank.com.br")
    }

    @Test("an acquirer descriptor cannot give a subscription the bank's logo")
    func acquirerDoesNotLeakIntoServices() {
        // THE reason `kind` exists. 'NU PAGAMENTOS' appears on Brazilian statements as
        // the ACQUIRER, so a subscription billed through Nubank would have matched the
        // bank row and worn its logo — and once R4 reads patterns, worse than that.
        #expect(BrandCatalog.entry(for: "NU PAGAMENTOS 12345 SOMESHOP", in: catalog, kind: .service) == nil)
        #expect(BrandCatalog.entry(for: "C6 BANK", in: catalog, kind: .service) == nil)
    }

    @Test("and a bank cannot be given a service's logo either")
    func servicesDoNotLeakIntoInstitutions() {
        // The symmetric half: a bank whose name contains a service pattern must not
        // borrow that service's mark.
        #expect(BrandCatalog.entry(for: "Netflix", in: catalog, kind: .institution) == nil)
        #expect(BrandCatalog.entry(for: "TRUELINE VALVE CORPORATION", in: catalog, kind: .institution) == nil)
    }

    @Test("the fetch set is still every domain, both kinds")
    func prefetchCoversBothKinds() {
        // The privacy property (v38) depends on fetching the WHOLE catalog. Filtering
        // this by kind would make the request set describe which surfaces the user is
        // looking at — a smaller version of the leak the padding prevents.
        let domains = BrandCatalog.allDomains(in: catalog)
        #expect(domains.contains("nubank.com.br"))
        #expect(domains.contains("c6bank.com.br"))
        #expect(domains.contains("netflix.com"))
    }
}
