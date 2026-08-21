import Testing
import Foundation
import Security
@testable import Signu


@Suite("Keychain availability")
struct KeychainAvailabilityTests {

    private let account = "signu.keychain.availability.probe"

    @Test("the app can write and read back a keychain item")
    func roundTrip() throws {
        let service = "pro.signu.tests"
        let secret = Data("probe".utf8)

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
            print("""
                SKIPPED KeychainAvailability: this build has no keychain \
                entitlement (-34018), so it could not persist a session. \
                Expected for a build made with CODE_SIGNING_ALLOWED=NO; never \
                acceptable for one a user signs into.
                """)
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
