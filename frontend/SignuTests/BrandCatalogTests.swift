import Testing
import Foundation
@testable import Signu


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


    @Test("an exact name wins")
    func exactName() {
        #expect(BrandCatalog.entry(for: "Netflix", in: catalog, kind: .service)?.domain == "netflix.com")
    }

    @Test("case and accents do not matter")
    func caseAndAccents() {
        #expect(BrandCatalog.entry(for: "estadao", in: catalog, kind: .service)?.brandName == "Estadão")
        #expect(BrandCatalog.entry(for: "ESTADÃO", in: catalog, kind: .service)?.brandName == "Estadão")
    }

    @Test("a pattern matches when the name does not")
    func patternFallback() {
        #expect(BrandCatalog.entry(for: "Netflix.com Brasil", in: catalog, kind: .service)?.domain == "netflix.com")
    }

    @Test("the longest pattern wins")
    func longestPatternWins() {
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
        #expect(BrandCatalog.entry(for: "Movies (mine)", in: catalog, kind: .service) == nil)
    }


    @Test("every domain is fetched, including merchants nobody is subscribed to")
    func allDomainsIsUserIndependent() {
        let domains = BrandCatalog.allDomains(in: catalog)
        #expect(domains == [
            "amazon.com", "amazon.com.br", "c6bank.com.br", "estadao.com.br",
            "netflix.com", "nubank.com.br", "steampowered.com",
        ])
    }

    @Test("a merchant with no domain is simply not fetched")
    func nilDomainsAreSkipped() {
        #expect(!BrandCatalog.allDomains(in: catalog).contains(""))
        #expect(BrandCatalog.allDomains(in: catalog).count == 7)
    }

    @Test("the mock catalog lists services the fixtures do not subscribe to")
    func mockCatalogIsNotDerivedFromTheUser() async throws {
        let p = MockDataProvider()
        let entries = try await p.brandCatalog()
        let subscribed = Set(try await p.subscriptions().map { BrandCatalog.normalise($0.serviceName) })
        let unsubscribed = entries.filter { !subscribed.contains(BrandCatalog.normalise($0.brandName)) }
        #expect(!unsubscribed.isEmpty, "the catalog must describe the world, not the account")
    }


    @Test("Steam is found through Valve's billing descriptor, not its name")
    func steamViaTruelineValve() throws {
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
        let steam = try #require(BrandCatalog.entry(for: "Steam", in: catalog, kind: .service))
        #expect(steam.subscriptionOnly == false)
        let netflix = try #require(BrandCatalog.entry(for: "Netflix", in: catalog, kind: .service))
        #expect(netflix.subscriptionOnly)
    }


    @Test("a bank is found through the label the app derives for it")
    func institutionsResolve() throws {
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
        #expect(BrandCatalog.entry(for: "NU PAGAMENTOS 12345 SOMESHOP", in: catalog, kind: .service) == nil)
        #expect(BrandCatalog.entry(for: "C6 BANK", in: catalog, kind: .service) == nil)
    }

    @Test("and a bank cannot be given a service's logo either")
    func servicesDoNotLeakIntoInstitutions() {
        #expect(BrandCatalog.entry(for: "Netflix", in: catalog, kind: .institution) == nil)
        #expect(BrandCatalog.entry(for: "TRUELINE VALVE CORPORATION", in: catalog, kind: .institution) == nil)
    }

    @Test("the fetch set is still every domain, both kinds")
    func prefetchCoversBothKinds() {
        let domains = BrandCatalog.allDomains(in: catalog)
        #expect(domains.contains("nubank.com.br"))
        #expect(domains.contains("c6bank.com.br"))
        #expect(domains.contains("netflix.com"))
    }
}
