import Testing
import Foundation
@testable import Signu


@Suite("Avatar cache (v54)")
@MainActor
struct AvatarStoreTests {

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

        await store.load(path: nil, using: provider)
        #expect(store.current(for: path) == nil)
    }

    @Test("a failed download does not become permanent for the session")
    func failureIsRetried() async throws {
        let provider = MockDataProvider()
        let missing = "\(UUID().uuidString.lowercased())/1.jpg"

        let store = AvatarStore()
        await store.load(path: missing, using: provider)
        #expect(store.current(for: missing) == nil)

        try await provider.setAvatar(jpeg: png)
        let real = try #require(try await provider.profile().avatarPath)
        await store.load(path: real, using: provider)
        #expect(store.current(for: real) != nil)
    }

    @Test("current() answers only for the path it holds")
    func currentIsPathScoped() async throws {
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
