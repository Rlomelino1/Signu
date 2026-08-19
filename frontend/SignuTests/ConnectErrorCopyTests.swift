import Testing
import Foundation
@testable import Signu


@Suite("Connect error copy (v53)")
struct ConnectErrorCopyTests {

    @Test("the code that reached a user becomes a sentence with a way out")
    func knownCode() {
        let message = ConnectErrorCopy.message(for: "ITEM_USER_ALREADY_EXISTS")
        #expect(message.contains("already connected"))
        #expect(message.contains("ITEM_USER_ALREADY_EXISTS") == false, "the enum must not survive")
        #expect(message.contains("Settings"), "it must say where to go")
    }

    @Test("case is not load-bearing")
    func caseInsensitive() {
        #expect(
            ConnectErrorCopy.message(for: "invalid_credentials")
                == ConnectErrorCopy.message(for: "INVALID_CREDENTIALS")
        )
    }

    @Test("Signu's own sentences pass through untouched")
    func serverSentencesSurvive() {
        let server = "platinum ···· 4321 is already connected through Nu Pagamentos S.A. "
            + "Remove that bank first if you meant to reconnect it."
        #expect(ConnectErrorCopy.message(for: server) == server)
    }

    @Test("an unknown code is kept, and gains advice rather than losing itself")
    func unknownCodeIsPreserved() {
        let message = ConnectErrorCopy.message(for: "SOME_UNMAPPED_PLUGGY_CODE")
        #expect(message.contains("SOME_UNMAPPED_PLUGGY_CODE"), "the diagnostic must survive")
        #expect(message.contains("Trying again"))
    }

    @Test("prose from Pluggy is left alone, not decorated as a code")
    func proseIsNotTreatedAsACode() {
        let prose = "Pluggy Connect failed to load"
        #expect(ConnectErrorCopy.message(for: prose) == prose)
    }

    @Test("an empty failure still says something true")
    func emptyMessage() {
        for raw in ["", "   ", "\n"] {
            let message = ConnectErrorCopy.message(for: raw)
            #expect(message.isEmpty == false)
            #expect(message.contains("Try again"))
        }
    }

    @Test("a short token is not mistaken for a code")
    func shortTokensAreProse() {
        #expect(ConnectErrorCopy.message(for: "404") == "404")
    }


    @Test("a trial-plan refusal does not tell the user to try again")
    func trialPlanIsNotRetryable() {
        let message = ConnectErrorCopy.message(for: "TRIAL_CLIENT_ITEM_CREATE_NOT_ALLOWED")
        #expect(!message.contains("Trying again"), "\(message)")
        #expect(!message.contains("this code is what to search for"), "\(message)")
        #expect(message.contains("MeuPluggy"))
        #expect(message.contains("Retrying won't help"))
    }

    @Test("the raw code no longer reaches the screen for that case")
    func trialPlanCodeIsTranslated() {
        let message = ConnectErrorCopy.message(for: "trial_client_item_create_not_allowed")
        #expect(!message.contains("TRIAL_CLIENT"))
        #expect(message.contains("Pluggy production access"))
    }
}
