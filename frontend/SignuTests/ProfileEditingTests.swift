import Testing
import Foundation
@testable import Signu

// The profile writes and what the screens read back (v47), through the mock —
// which implements the same protocol the live provider does, including the
// fallback semantics that decide whether Home greets by name at all.

@Suite("Profile editing (v47)")
@MainActor
struct ProfileEditingTests {

    private func provider() -> MockDataProvider { MockDataProvider() }
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    // MARK: - The name

    @Test("a name is saved and read back")
    func nameRoundTrips() async throws {
        let p = provider()
        try await p.setDisplayName("Rafael")
        let profile = try await p.profile()
        #expect(profile.displayName == "Rafael")
        #expect(profile.displayNameIsFallback == false)
    }

    @Test("clearing the name puts the email back, marked as standing in")
    func clearingFallsBackToEmail() async throws {
        // The same shape as clearing a nickname: "no name" is a state the user is
        // allowed to return to, and the read must say the value is not a name.
        let p = provider()
        try await p.setDisplayName(nil)
        let profile = try await p.profile()
        #expect(profile.displayName == profile.email)
        #expect(profile.displayNameIsFallback)
    }

    @Test("Home greets without a name rather than reading an email address")
    func homeDropsTheNameWhenItIsAFallback() async throws {
        // The reported bug: Home said "Good morning, you@example.com".
        let p = provider()
        try await p.setDisplayName(nil)
        let home = try await p.homePayload()
        #expect(home.firstName == nil)
        // The monogram still has to come from somewhere, and it is the email's
        // letter — never the "@" that `displayName.prefix(1)` would give for an
        // address starting with one.
        let profile = try await p.profile()
        #expect(home.initial == String(profile.email.prefix(1)).uppercased())
    }

    @Test("Home greets by first name only, when there is one")
    func homeUsesTheFirstName() async throws {
        let p = provider()
        try await p.setDisplayName("Rafael Pastor Lomelino Mota")
        let home = try await p.homePayload()
        #expect(home.firstName == "Rafael")
        #expect(home.initial == "R")
    }

    @Test("the Settings row invites a name instead of restating the address")
    func settingsRowFlagsTheFallback() async throws {
        let p = provider()
        try await p.setDisplayName(nil)
        #expect(try await p.settingsPayload().displayNameIsFallback)

        try await p.setDisplayName("Rafael")
        let named = try await p.settingsPayload()
        #expect(named.displayNameIsFallback == false)
        #expect(named.displayName == "Rafael")
    }

    // MARK: - The picture

    @Test("an uploaded picture is reachable at the path the profile names")
    func avatarRoundTrips() async throws {
        let p = provider()
        try await p.setAvatar(jpeg: jpeg)
        let path = try #require(try await p.profile().avatarPath)
        #expect(try await p.avatarData(path: path) == jpeg)
        // Scoped to the user's own folder, which is what Migration #11's policies
        // enforce server-side; the client must not construct anything else.
        #expect(path.hasPrefix(try await p.profile().id.uuidString.lowercased() + "/"))
        #expect(path.hasSuffix(".jpg"))
    }

    @Test("the path is what the Settings row and Home both carry")
    func payloadsCarryThePath() async throws {
        let p = provider()
        try await p.setAvatar(jpeg: jpeg)
        let path = try #require(try await p.profile().avatarPath)
        #expect(try await p.settingsPayload().avatarPath == path)
        #expect(try await p.homePayload().avatarPath == path)
    }

    @Test("removing the picture clears the column and the object")
    func removalClearsBoth() async throws {
        let p = provider()
        try await p.setAvatar(jpeg: jpeg)
        let path = try #require(try await p.profile().avatarPath)

        try await p.removeAvatar()
        #expect(try await p.profile().avatarPath == nil)
        // The object must be gone too, not merely unreferenced: a store that still
        // answers would let a cache render a picture the user deleted.
        await #expect(throws: (any Error).self) { try await p.avatarData(path: path) }
    }

    @Test("removing when there is no picture is not an error")
    func removalIsIdempotent() async throws {
        let p = provider()
        try await p.removeAvatar()
        #expect(try await p.profile().avatarPath == nil)
    }

    @Test("a missing object throws rather than reporting zero bytes")
    func missingObjectThrows() async throws {
        // The private bucket 404s, and a store that treated "missing" as "empty"
        // would cache the emptiness and never recover.
        let p = provider()
        await #expect(throws: (any Error).self) {
            try await p.avatarData(path: "nobody/1.jpg")
        }
    }
}
