import Testing
import Foundation
@testable import Signu

// The avatar cache (v54), and specifically the two ways it destroyed or refused
// good state.
//
// Both were found in a Release build rather than by a test: the photo rendered
// yesterday and showed a monogram today, with an empty cache directory. That is the
// shape of a cache that deletes on failure.

@Suite("Avatar cache (v54)")
@MainActor
struct AvatarStoreTests {

    /// A 1×1 PNG. Real bytes, because the store decodes what it is given and a
    /// placeholder would pass the write and fail the decode.
    private var png: Data {
        Data(base64Encoded: """
            iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==
            """)!
    }

    @Test("an uploaded picture loads and renders")
    func loadsWhatWasUploaded() async throws {
        let provider = MockDataProvider()
        try await provider.setAvatar(jpeg: png)
        let path = try #require(try await provider.profile().avatarPath)

        let store = AvatarStore()
        await store.load(path: path, using: provider)
        #expect(store.current(for: path) != nil)
    }

    @Test("a removed picture is dropped from the cache")
    func nilClears() async throws {
        let provider = MockDataProvider()
        try await provider.setAvatar(jpeg: png)
        let path = try #require(try await provider.profile().avatarPath)

        let store = AvatarStore()
        await store.load(path: path, using: provider)
        #expect(store.current(for: path) != nil)

        // nil means the profile SAYS there is none — the deletion case, where
        // keeping the cache would render a picture the user just removed.
        await store.load(path: nil, using: provider)
        #expect(store.current(for: path) == nil)
    }

    @Test("a failed download does not become permanent for the session")
    func failureIsRetried() async throws {
        // v54's second half. The failure used to be remembered, so one bad download
        // meant a monogram until the app restarted — and nothing calls this at
        // render time, so there was never a retry storm to protect against.
        let provider = MockDataProvider()
        let missing = "\(UUID().uuidString.lowercased())/1.jpg"

        let store = AvatarStore()
        await store.load(path: missing, using: provider)   // throws inside, no image
        #expect(store.current(for: missing) == nil)

        // The same path becomes available; the next refresh must pick it up.
        try await provider.setAvatar(jpeg: png)
        let real = try #require(try await provider.profile().avatarPath)
        await store.load(path: real, using: provider)
        #expect(store.current(for: real) != nil)
    }

    @Test("current() answers only for the path it holds")
    func currentIsPathScoped() async throws {
        // The path IS the cache key (Migration #11), so asking about a different
        // path must miss rather than return a stale image.
        let provider = MockDataProvider()
        try await provider.setAvatar(jpeg: png)
        let path = try #require(try await provider.profile().avatarPath)

        let store = AvatarStore()
        await store.load(path: path, using: provider)
        #expect(store.current(for: path) != nil)
        #expect(store.current(for: "someone-else/9.jpg") == nil)
        #expect(store.current(for: nil) == nil)
    }
}
