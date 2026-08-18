import Testing
import Foundation
@testable import Signu

// What the connect surface says when it fails (v53).
//
// `ITEM_USER_ALREADY_EXISTS` reached a user verbatim on 2026-08-17. Translating
// codes is the fix, but the interesting requirement is the other half: an
// unrecognised code must be KEPT, not swallowed into "something went wrong". v40
// already cost an hour to a message four steps from its cause.

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
        // The v53 duplicate check writes this. Paraphrasing it would throw away the
        // account name the user needs, which is the whole point of writing it.
        let server = "platinum ···· 2049 is already connected through Nu Pagamentos S.A. "
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
        // "404" or "N/A" are not codes to append advice to; they are just short.
        #expect(ConnectErrorCopy.message(for: "404") == "404")
    }

    // MARK: - The plan boundary (v68)

    @Test("a trial-plan refusal does not tell the user to try again")
    func trialPlanIsNotRetryable() {
        // Hit for real on 2026-08-18 while trying to connect a bank directly. The
        // generic fallback appended "Trying again often clears it" and left a Try
        // again button on screen that could never succeed: Pluggy refuses item
        // creation for real bank connectors on a trial plan, and no amount of
        // retrying changes a plan.
        let message = ConnectErrorCopy.message(for: "TRIAL_CLIENT_ITEM_CREATE_NOT_ALLOWED")
        #expect(!message.contains("Trying again"), "\(message)")
        #expect(!message.contains("this code is what to search for"), "\(message)")
        // And it says what IS still possible, because a dead end with no alternative
        // is only half an answer.
        #expect(message.contains("MeuPluggy"))
        #expect(message.contains("Retrying won't help"))
    }

    @Test("the raw code no longer reaches the screen for that case")
    func trialPlanCodeIsTranslated() {
        // The fallback deliberately SHOWS unknown codes (v40's lesson: never delete
        // the only diagnostic). This one is known now, so the enum is gone from the
        // copy — the distinction between "cannot interpret" and "interpreted".
        let message = ConnectErrorCopy.message(for: "trial_client_item_create_not_allowed")
        #expect(!message.contains("TRIAL_CLIENT"))
        // Lowercase input still matches: Pluggy sends screaming snake case, but the
        // lookup upcases rather than trusting the wire format.
        #expect(message.contains("Pluggy production access"))
    }
}
