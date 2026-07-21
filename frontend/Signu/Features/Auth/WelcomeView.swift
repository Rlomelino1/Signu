import SwiftUI

/// Welcome carousel (16a — mockups 21a / 21a-second / 21a-third).
/// Upper zone = wordmark + auto-advancing carousel; lower zone = anchored
/// CTA stack that never moves. Reads no user state.
struct WelcomeView: View {
    var onCreateAccount: () -> Void = {}
    var onGoogle: () -> Void = {}
    var onSignIn: () -> Void = {}

    @State private var index = 0
    @State private var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let advance = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    private let slides = WelcomeSlide.all

    var body: some View {
        VStack(spacing: 0) {
            wordmark
                .padding(.top, 14)

            TabView(selection: $index) {
                ForEach(slides.indices, id: \.self) { i in
                    slides[i].view.tag(i)
                        .padding(.horizontal, SignuMetric.screenPadding)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .simultaneousGesture(DragGesture().onChanged { _ in paused = true })
            .onReceive(advance) { _ in
                guard !paused, !reduceMotion else { return }
                withAnimation(.easeInOut) { index = (index + 1) % slides.count }
            }

            dots.padding(.bottom, 18)
            ctaStack.padding(.horizontal, SignuMetric.screenPadding).padding(.bottom, 8)
        }
        .background(SignuColor.paper)
    }

    private var wordmark: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SignuColor.ink)
                .frame(width: 64, height: 64)
                .overlay {
                    Text("S").font(SignuFont.font(32, .bold)).foregroundStyle(SignuColor.onInk)
                }
            Text("Signu")
                .font(SignuFont.font(32, .bold))
                .foregroundStyle(SignuColor.textPrimary)
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? SignuColor.ink : SignuColor.textTertiary.opacity(0.5))
                    .frame(width: i == index ? 24 : 8, height: 8)
                    .onTapGesture {
                        paused = true
                        withAnimation(.easeInOut) { index = i }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    private var ctaStack: some View {
        VStack(spacing: 12) {
            Button("Create account", action: onCreateAccount)
                .buttonStyle(.signuPrimary)
            Button(action: onGoogle) {
                HStack(spacing: 10) {
                    GoogleGLogo()
                    Text("Continue with Google")
                }
            }
            .buttonStyle(.signuSecondary)
            Button(action: onSignIn) {
                (
                    Text("Already have an account? ").foregroundStyle(SignuColor.textSecondary)
                    + Text("Sign in").foregroundStyle(SignuColor.textPrimary).bold()
                )
                .font(.signuBody)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            TermsLine()
        }
    }
}

/// One carousel slide: swappable mock content + headline + body.
struct WelcomeSlide {
    let view: AnyView

    static let all: [WelcomeSlide] = [
        WelcomeSlide(view: AnyView(SlideList())),
        WelcomeSlide(view: AnyView(SlidePriceHike())),
        WelcomeSlide(view: AnyView(SlideFound())),
    ]
}

/// Shared slide layout: content top-anchored at a shared position with a
/// fixed gap reserved above the page-dot indicator, so all three slides
/// (different heights) keep a consistent gap instead of sagging into the dots.
private struct SlideScaffold<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .padding(.bottom, 24)   // fixed gap above the dots
    }
}

// MARK: - Slide 1: the all-in-one-place promise

private struct SlideList: View {
    var body: some View {
        SlideScaffold {
            VStack(spacing: 8) {
                mockRow("Netflix", "Renews Jul 22", "R$ 44,90", faded: false)
                mockRow("Spotify", "Renews Jul 15", "R$ 21,90", faded: false)
                mockRow("iCloud+", "Renews Jul 21", "R$ 14,90", faded: true)
            }
            SlideCopy(
                title: "Know what you're really paying for.",
                message: "Every subscription in one place, with the next renewal always in sight."
            )
        }
    }

    private func mockRow(_ name: String, _ sub: String, _ amount: String, faded: Bool) -> some View {
        HStack(spacing: 12) {
            ServiceAvatar(name: name)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.signuRowTitle).foregroundStyle(SignuColor.textPrimary)
                Text(sub).font(.signuSubtitle).foregroundStyle(SignuColor.textSecondary)
            }
            Spacer()
            Text(amount).font(.signuRowTitle).foregroundStyle(SignuColor.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.cardRadius, style: .continuous))
        .opacity(faded ? 0.5 : 1)
    }
}

// MARK: - Slide 2: price-hike narration

private struct SlidePriceHike: View {
    var body: some View {
        SlideScaffold {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ServiceAvatar(name: "Spotify", size: 40)
                    Text("Spotify").font(.signuRowTitle).foregroundStyle(SignuColor.textPrimary)
                    Spacer()
                    StatusChip(text: "PRICE RAISED", tone: .warning)
                }
                HStack(spacing: 8) {
                    Text("R$ 19,90").font(.signuRowTitle).strikethrough().foregroundStyle(SignuColor.textSecondary)
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(SignuColor.textSecondary)
                    Text("R$ 21,90").font(.signuHeadline).foregroundStyle(SignuColor.gold)
                    Text("since May 15").font(.signuSubtitle).foregroundStyle(SignuColor.textSecondary)
                }
            }
            .padding(16)
            .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.cardRadius, style: .continuous))

            SlideCopy(
                title: "Catch every price hike.",
                message: "Signu compares each charge to the last one and flags the quiet increases."
            )
        }
    }
}

// MARK: - Slide 3: found-from-bank (teaches the tilde)

private struct SlideFound: View {
    // Descriptor is one non-breaking unit — it wraps whole (or drops to a new
    // line) at the "·", never mid-phrase.
    private let descriptor = "·\u{00A0}spotted\u{00A0}in\u{00A0}your\u{00A0}bank\u{00A0}activity"

    var body: some View {
        SlideScaffold {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ServiceAvatar(name: "Globoplay", size: 40)
                    Text("Globoplay").font(.signuRowTitle).foregroundStyle(SignuColor.textPrimary)
                    Spacer()
                    StatusChip(text: "FOUND", tone: .positive)
                }
                (
                    Text("~R$\u{00A0}24,90").font(.signuHeadline).foregroundStyle(SignuColor.textPrimary)
                    + Text("\u{00A0}/mo ").font(.signuSubtitle).foregroundStyle(SignuColor.textSecondary)
                    + Text(descriptor).font(.signuSubtitle).foregroundStyle(SignuColor.textSecondary)
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.cardRadius, style: .continuous))

            SlideCopy(
                title: "Found straight from your bank.",
                message: "Connect your bank and subscriptions show up on their own — even the ones you forgot."
            )
        }
    }
}

private struct SlideCopy: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(SignuFont.font(34, .bold))
                .foregroundStyle(SignuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(SignuFont.font(18))
                .foregroundStyle(SignuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Welcome (16a)") {
    WelcomeView()
}
