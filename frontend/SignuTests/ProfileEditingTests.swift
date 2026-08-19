import Testing
import Foundation
@testable import Signu


@Suite("Profile editing (v47)")
@MainActor
struct ProfileEditingTests {

    private func provider() -> MockDataProvider { MockDataProvider() }
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])


    @Test("a name is saved and read back")
    func nameRoundTrips() async throws {
        let p = provider()
        try await p.setDisplayName("Alex")
        let profile = try await p.profile()
        #expect(profile.displayName == "Alex")
        #expect(profile.displayNameIsFallback == false)
    }

    @Test("clearing the name puts the email back, marked as standing in")
    func clearingFallsBackToEmail() async throws {
        let p = provider()
        try await p.setDisplayName(nil)
        let profile = try await p.profile()
        #expect(profile.displayName == profile.email)
        #expect(profile.displayNameIsFallback)
    }

    @Test("Home greets without a name rather than reading an email address")
    func homeDropsTheNameWhenItIsAFallback() async throws {
        let p = provider()
        try await p.setDisplayName(nil)
        let home = try await p.homePayload()
        #expect(home.firstName == nil)
        let profile = try await p.profile()
        #expect(home.initial == String(profile.email.prefix(1)).uppercased())
    }

    @Test("Home greets by first name only, when there is one")
    func homeUsesTheFirstName() async throws {
        let p = provider()
        try await p.setDisplayName("Alex Bernard Cassidy Rivera")
        let home = try await p.homePayload()
        #expect(home.firstName == "Alex")
        #expect(home.initial == "A")
    }

    @Test("the Settings row invites a name instead of restating the address")
    func settingsRowFlagsTheFallback() async throws {
        let p = provider()
        try await p.setDisplayName(nil)
        #expect(try await p.settingsPayload().displayNameIsFallback)

        try await p.setDisplayName("Alex")
        let named = try await p.settingsPayload()
        #expect(named.displayNameIsFallback == false)
        #expect(named.displayName == "Alex")
    }



    @Test("the stored email counts as no name, whatever its case or padding")
    func storedEmailIsAFallback() {
        let email = "someone@example.test"
        for stored in [email, "SOMEONE@Example.test", "  someone@example.test  "] {
            let resolved = ProfileName.resolve(stored: stored, email: email)
            #expect(resolved.isFallback, "\(stored) should read as no name")
            #expect(resolved.display.isEmpty == false)
        }
    }

    @Test("nil and blank are the same state as the stored email")
    func nilAndBlankAreFallbacks() {
        let email = "someone@example.test"
        for stored in [nil, "", "   "] as [String?] {
            let resolved = ProfileName.resolve(stored: stored, email: email)
            #expect(resolved.isFallback)
            #expect(resolved.display == email)
        }
    }

    @Test("a real name is a name, and is not trimmed away")
    func realNameSurvives() {
        let resolved = ProfileName.resolve(stored: "  Alex  ", email: "someone@example.test")
        #expect(resolved.isFallback == false)
        #expect(resolved.display == "Alex")
    }

    @Test("a name that merely contains the address is still a name")
    func nameContainingTheAddressIsNotAFallback() {
        let resolved = ProfileName.resolve(
            stored: "someone@example.test (Alex)", email: "someone@example.test"
        )
        #expect(resolved.isFallback == false)
    }

    @Test("Home declines the greeting when the stored name is the address")
    func homeDeclinesTheStoredEmail() async throws {
        let p = provider()
        let email = try await p.profile().email
        try await p.setDisplayName(email)
        let home = try await p.homePayload()
        #expect(home.firstName == nil, "the greeting must not read an address aloud")
        #expect(try await p.settingsPayload().displayNameIsFallback)
    }


    @Test("an uploaded picture is reachable at the path the profile names")
    func avatarRoundTrips() async throws {
        let p = provider()
        try await p.setAvatar(jpeg: jpeg)
        let path = try #require(try await p.profile().avatarPath)
        #expect(try await p.avatarData(path: path) == jpeg)
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
        let p = provider()
        await #expect(throws: (any Error).self) {
            try await p.avatarData(path: "nobody/1.jpg")
        }
    }
}
