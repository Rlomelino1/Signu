import Testing
import Foundation
@testable import Signu


@Suite("Auth cooldown (v48)")
struct AuthCooldownTests {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)


    @Test("a fresh send has the whole window")
    func freshSend() {
        #expect(AuthCooldown.remaining(since: now, now: now) == AuthCooldown.seconds)
    }

    @Test("no send means nothing to wait for")
    func noSend() {
        #expect(AuthCooldown.remaining(since: nil, now: now) == 0)
    }

    @Test("the window burns down with elapsed time and stops at zero")
    func burnsDown() {
        let sent = now.addingTimeInterval(-30)
        #expect(AuthCooldown.remaining(since: sent, now: now) == AuthCooldown.seconds - 30)

        let long = now.addingTimeInterval(-Double(AuthCooldown.seconds) * 10)
        #expect(AuthCooldown.remaining(since: long, now: now) == 0)
    }

    @Test("a clock that jumped backwards cannot read as a longer wait")
    func clampedForwards() {
        let future = now.addingTimeInterval(600)
        #expect(AuthCooldown.remaining(since: future, now: now) == AuthCooldown.seconds)
    }


    @Test("nothing to forget when nothing was sent")
    func neverSent() {
        #expect(AuthCooldown.shouldForget(sentAt: nil, now: now) == false)
    }

    @Test("a live cooldown is kept, including at its last second")
    func keptWhileCoolingDown() {
        #expect(AuthCooldown.shouldForget(sentAt: now, now: now) == false)
        let almost = now.addingTimeInterval(-Double(AuthCooldown.seconds - 1))
        #expect(AuthCooldown.shouldForget(sentAt: almost, now: now) == false)
    }

    @Test("an expired cooldown is forgotten, from the exact boundary onwards")
    func forgottenOnceExpired() {
        let exactly = now.addingTimeInterval(-Double(AuthCooldown.seconds))
        #expect(AuthCooldown.shouldForget(sentAt: exactly, now: now))

        let wellPast = now.addingTimeInterval(-Double(AuthCooldown.seconds) * 100)
        #expect(AuthCooldown.shouldForget(sentAt: wellPast, now: now))
    }

    @Test("a backwards clock jump keeps the state rather than dropping it")
    func backwardsClockKeepsIt() {
        let future = now.addingTimeInterval(3600)
        #expect(AuthCooldown.shouldForget(sentAt: future, now: now) == false)
    }
}
