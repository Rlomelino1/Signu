import SwiftUI

/// The boot splash, shown while `SessionStore` restores the session.
///
/// The two halves of the mark slide apart and back together, and a line of copy
/// rotates underneath. Both loops start **at rest** rather than at the top of
/// the designed cycle: a restore is usually well under a second, so the first
/// frame is the one almost every launch actually sees. Starting mid-slide with
/// the copy still invisible would read as a flicker. The loop is there for the
/// boots that do take a while.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Height of the copy strip, and its distance from the bottom of the
    /// screen. The mark centres in what is left above them, which raises it
    /// (20 + 116) / 2 = 68pt above the screen's centre — the constant the
    /// launch storyboard hard-codes to place its own copy of the mark. Change
    /// either of these and that constant changes with them.
    static let copyHeight: CGFloat = 20
    static let copyBottomInset: CGFloat = 116

    private static let phrases = [
        "Waking things up…",
        "Syncing your charges…",
        "Checking what renews next…",
        "Lining everything up…",
    ]
    /// One full pass through all four phrases.
    private static let copyCycle: Double = 9.2
    /// One phrase's turn on screen. Four of them fill the cycle.
    private static var phraseInterval: Double { copyCycle / Double(phrases.count) }
    /// Where the cycle starts: the instant the first phrase reaches full
    /// opacity, so a launch opens on a readable line rather than a blank strip.
    private static let copyStart: Double = 0.05 * copyCycle
    /// How far a phrase travels as it arrives and leaves.
    private static let copyRise: CGFloat = 9

    var body: some View {
        ZStack {
            SignuColor.bootBackdrop

            VStack(spacing: 0) {
                mark
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)

                copy
                    .frame(height: Self.copyHeight)
                    .padding(.horizontal, 40)
                    .padding(.bottom, Self.copyBottomInset)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var mark: some View {
        if reduceMotion {
            SignuArcsMark()
        } else {
            KeyframeAnimator(initialValue: ArcPhase(), repeating: true) { phase in
                SignuArcsMark(
                    upperOffset: phase.upper,
                    lowerOffset: -phase.upper,
                    upperOpacity: phase.opacity,
                    lowerOpacity: phase.opacity
                )
            } keyframes: { _ in
                // Re-phased so t=0 is the resting state: hold, part, wait,
                // return with a small overshoot, settle. Same 4.8s cycle and
                // the same distances as the design, entered where a fast boot
                // is best served.
                KeyframeTrack(\.upper) {
                    LinearKeyframe(0, duration: 2.352)
                    CubicKeyframe(-90, duration: 0.576)
                    LinearKeyframe(-90, duration: 0.768)
                    CubicKeyframe(7, duration: 0.768)
                    CubicKeyframe(0, duration: 0.336)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 2.352)
                    CubicKeyframe(0, duration: 0.576)
                    LinearKeyframe(0, duration: 0.768)
                    CubicKeyframe(1, duration: 0.768)
                    LinearKeyframe(1, duration: 0.336)
                }
            }
        }
    }

    @ViewBuilder
    private var copy: some View {
        if reduceMotion {
            phrase(Self.phrases[0])
        } else {
            // All four lines are stacked and driven off one clock, the way the
            // design layers four elements with staggered delays. A single
            // swapped-out label cross-fades for as long as its transition runs,
            // which ghosts two lines over each other; here each line's opacity
            // is a function of the phase, so the handoff is as tight as drawn.
            KeyframeAnimator(initialValue: Self.copyStart, repeating: true) { clock in
                ZStack {
                    ForEach(Self.phrases.indices, id: \.self) { index in
                        let step = Self.step(clock, index)
                        phrase(Self.phrases[index])
                            .opacity(Self.opacity(at: step))
                            .offset(y: Self.rise(at: step))
                    }
                }
            } keyframes: { _ in
                LinearKeyframe(Self.copyStart + Self.copyCycle, duration: Self.copyCycle)
            }
        }
    }

    private func phrase(_ text: String) -> some View {
        Text(text)
            .font(SignuFont.font(13.5, .semibold))
            .kerning(0.2)
            .foregroundStyle(SignuColor.bootMark.opacity(0.55))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Where one phrase sits in its own 0…1 cycle, given the shared clock.
    private static func step(_ clock: Double, _ index: Int) -> Double {
        let shifted = clock - Double(index) * phraseInterval
        return (shifted.truncatingRemainder(dividingBy: copyCycle) + copyCycle)
            .truncatingRemainder(dividingBy: copyCycle) / copyCycle
    }

    /// Fades in by 5%, holds to 21%, gone by 26%, absent for the rest.
    private static func opacity(at step: Double) -> Double {
        switch step {
        case ..<0.05: step / 0.05
        case ..<0.21: 1
        case ..<0.26: 1 - (step - 0.21) / 0.05
        default: 0
        }
    }

    /// Rises from below, rests, and keeps rising as it goes.
    private static func rise(at step: Double) -> CGFloat {
        switch step {
        case ..<0.05: copyRise * (1 - CGFloat(step / 0.05))
        case ..<0.21: 0
        case ..<0.26: -copyRise * CGFloat((step - 0.21) / 0.05)
        default: -copyRise
        }
    }

    /// Displacement and opacity of the upper half. The lower half mirrors it,
    /// so one track drives both.
    private struct ArcPhase {
        var upper: CGFloat = 0
        var opacity: Double = 1
    }
}

#Preview("Splash") {
    SplashView()
}
