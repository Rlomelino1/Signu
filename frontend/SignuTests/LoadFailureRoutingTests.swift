import Testing
@testable import Signu

// Where a failed read goes, given what is already on screen (v72).
//
// Both pull-to-refresh handlers were `try? await provider.refresh()`. The
// `refresh()` VERDICT is documented as ignorable there — the user asked, so the
// payload is re-read either way — but `try?` discarded the ERROR too. A pull with
// no network threw inside `refresh()`, the throw vanished, the re-read returned the
// cache that `reload()` had failed to replace, and the same stale rows came back
// under a completed spinner. A gesture that appears to have worked is worse than one
// that appears to do nothing.
//
// Fixing the swallow exposed the harder question this enum answers: what should a
// failed re-read do to a screen that already has good data on it? `load()` cleared
// `payload` unconditionally, which was safe while it only ran on first load and
// became wrong the moment pull-to-refresh called it — one bad re-read would trade a
// working screen for a retry button.

@Suite("Load failure routing (v72)")
struct LoadFailureRoutingTests {

    @Test("with nothing on screen, the error IS the screen")
    func replacesAnEmptyScreen() {
        #expect(LoadFailureRoute.of(hasPayload: false) == .replaceScreen)
    }

    @Test("with something on screen, keep it and report the failure elsewhere")
    func keepsDataAlreadyShowing() {
        // A failure view here would say LESS than the data already on screen
        // supports, which is the one outcome this app refuses.
        #expect(LoadFailureRoute.of(hasPayload: true) == .reportOnly)
    }
}
