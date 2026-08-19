import Testing
@testable import Signu


@Suite("Load failure routing (v72)")
struct LoadFailureRoutingTests {

    @Test("with nothing on screen, the error IS the screen")
    func replacesAnEmptyScreen() {
        #expect(LoadFailureRoute.of(hasPayload: false) == .replaceScreen)
    }

    @Test("with something on screen, keep it and report the failure elsewhere")
    func keepsDataAlreadyShowing() {
        #expect(LoadFailureRoute.of(hasPayload: true) == .reportOnly)
    }
}
