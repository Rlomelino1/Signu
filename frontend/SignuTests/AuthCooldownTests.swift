import Testing
import Foundation
@testable import Signu

// The cooldown arithmetic, and v48's "forget it now" rule on top of it.
//
// Pinned here because both are decisions about how long a piece of UI keeps
// claiming something. The row said "Check your email for a link" for the rest of
// the process lifetime before v48 — 120 seconds of truth followed by an unbounded
// stale claim — and the fix is one boolean that has to be right at both edges.

@Suite("Auth cooldown (v48)")
struct AuthCooldownTests {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    // MARK: - remaining

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
        // Clamped at both ends: a future stamp must not produce more than the
        // window, or the row would claim a wait it never set.
        let future = now.addingTimeInterval(600)
        #expect(AuthCooldown.remaining(since: future, now: now) == AuthCooldown.seconds)
    }

    // MARK: - shouldForget (v48)

    @Test("nothing to forget when nothing was sent")
    func neverSent() {
        #expect(AuthCooldown.shouldForget(sentAt: nil, now: now) == false)
    }

    @Test("a live cooldown is kept, including at its last second")
    func keptWhileCoolingDown() {
        #expect(AuthCooldown.shouldForget(sentAt: now, now: now) == false)
        // One second short of the window. Forgetting here would drop the state
        // while Supabase would still rate-limit the resend, which is the failure
        // v19 built the countdown to prevent.
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
        // `remaining` clamps a future stamp to the full window, so this reads as
        // "still cooling down" and the row keeps its sent state. The safe
        // direction: the alternative offers a Resend that silently no-ops.
        let future = now.addingTimeInterval(3600)
        #expect(AuthCooldown.shouldForget(sentAt: future, now: now) == false)
    }
}
