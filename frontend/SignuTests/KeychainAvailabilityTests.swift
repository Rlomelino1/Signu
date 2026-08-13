import Testing
import Foundation
import Security
@testable import Signu

// Can this build store a session at all?
//
// Supabase's `AuthClient` keeps the session in the Keychain and nowhere else, so
// a Keychain that refuses writes produces a very confusing app: `signIn`
// succeeds, the gate flips on it, `currentSession` reads back nil, and every
// PostgREST request quietly falls back to the anon key — which Migration #1
// revoked everything from. The user sees "permission denied for table profiles"
// and nothing about signing in.
//
// That is not a hypothetical: it is exactly what a build with no entitlements
// did on the simulator, and the failing layer was four steps removed from the
// message on screen. This test names the precondition so the next person meets
// it as an assertion rather than as a mystery.
//
// It runs in the host app's process, so it inherits the app's entitlements —
// which is the whole point. A test bundle of its own would prove nothing about
// the app.

@Suite("Keychain availability")
struct KeychainAvailabilityTests {

    private let account = "signu.keychain.availability.probe"

    @Test("the app can write and read back a keychain item")
    func roundTrip() throws {
        let service = "pro.sinatra.signu.tests"
        let secret = Data("probe".utf8)

        // Clean slate, ignoring "not found".
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = secret
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        #expect(
            addStatus == errSecSuccess,
            """
            SecItemAdd failed with OSStatus \(addStatus). -34018 is \
            errSecMissingEntitlement: the build carries no keychain entitlement, \
            which happens when it is signed without a development team (or with \
            CODE_SIGNING_ALLOWED=NO). Supabase stores the session here and \
            nowhere else, so nothing will stay signed in.
            """
        )

        var query = base
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &item)
        #expect(readStatus == errSecSuccess, "SecItemCopyMatching failed with \(readStatus)")
        #expect(item as? Data == secret)

        SecItemDelete(base as CFDictionary)
    }
}
