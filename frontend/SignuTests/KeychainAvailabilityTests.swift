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
//
// AND IT SKIPS WHEN THE BUILD HAS NO KEYCHAIN ENTITLEMENT AT ALL.
//
// `CODE_SIGNING_ALLOWED=NO` — which CI passes, and which any local build can pass
// — produces an app with no entitlements, and the Keychain then refuses
// everything with -34018. Xcode's default simulator signing does attach one, and
// the Keychain works. That difference is the entire explanation of the outage this
// test was written during: the build handed over for testing had been made with
// that flag, so `signIn` succeeded, the session could not be stored,
// `currentSession` read back nil, and every request fell back to the anon key —
// surfacing as "permission denied for table profiles" four steps from the cause.
//
// The flag was also why an earlier run of this very test passed and appeared to
// exonerate the Keychain: it was run WITHOUT the flag. So the test now
// distinguishes "this build cannot have a keychain" (skip, and say so) from "this
// build has a keychain and it is broken" (fail), and never claims the first is
// evidence about the second.

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

        guard addStatus != errSecMissingEntitlement else {
            // -34018: no keychain entitlement, so there is nothing here to test.
            // An unsigned build (CI's `CODE_SIGNING_ALLOWED=NO`) lands here, and
            // that is a property of the build rather than a defect in the app —
            // but such a build can never keep a user signed in.
            Issue.record(
                """
                Skipped: this build has no keychain entitlement (-34018), so a \
                session could not be persisted by it. Expected for an unsigned \
                build; never acceptable for one a user signs into.
                """,
                severity: .warning
            )
            return
        }

        #expect(
            addStatus == errSecSuccess,
            """
            SecItemAdd failed with OSStatus \(addStatus) — and NOT with \
            -34018, so this build does have a keychain and it is refusing a \
            plain generic-password write. Supabase stores the session here and \
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
