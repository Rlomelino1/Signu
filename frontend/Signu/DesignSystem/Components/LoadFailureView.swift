import SwiftUI

/// What a screen shows when its read failed.
///
/// It exists because the app had no way to say this. Every read was `try?`, so a
/// thrown error and an empty account produced the same thing — `Color.clear` —
/// and a signed-in user whose data would not load got a blank page with a tab
/// bar, with nothing on screen or in a log naming the problem. "Renders nothing"
/// is the one outcome that tells the user nothing and tells us nothing.
///
/// The message is the underlying error's own words rather than a friendly
/// paraphrase. This is a personal-deployment app whose reader is also its
/// developer, and "Something went wrong" would delete the only useful part —
/// the same reasoning the connect flow and the four Edge Function actions use
/// when they surface a server's message verbatim.
/// Where a failed read goes, given what is already on screen.
///
/// One rule in one place because the two screens used to disagree about it. Home
/// gained a failure state; Subs kept rendering `Color.clear` for both "still
/// loading" and "the read threw", which is the exact bug the view above exists to
/// end. And neither screen had an answer for the harder case: a read that fails
/// while something good is already showing.
enum LoadFailureRoute: Equatable {
    /// Nothing is on screen, so the error IS the screen — `LoadFailureView`, with
    /// its retry.
    case replaceScreen
    /// Something is on screen. Keep it and report the error elsewhere: a failure
    /// view would say LESS than the data already showing supports, and a
    /// pull-to-refresh that empties a working screen is a worse outcome than the
    /// failure it set out to report.
    case reportOnly

    static func of(hasPayload: Bool) -> LoadFailureRoute {
        hasPayload ? .reportOnly : .replaceScreen
    }
}

struct LoadFailureView: View {
    let message: String
    /// Async, so the retry can await the reload and the button reflects it.
    var retry: () async -> Void

    @State private var retrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Couldn't load your data")
                .font(.signuSection)
                .foregroundStyle(SignuColor.textPrimary)

            Text(message)
                .font(.signuBody)
                .foregroundStyle(SignuColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    retrying = true
                    await retry()
                    retrying = false
                }
            } label: {
                if retrying {
                    ProgressView().tint(SignuColor.onInk)
                } else {
                    Text("Try again")
                }
            }
            .buttonStyle(.signuPrimary)
            .disabled(retrying)
        }
        .padding(20)
        .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.cardRadius, style: .continuous))
        .padding(.horizontal, SignuMetric.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

#Preview("Load failure") {
    LoadFailureView(message: "The data couldn’t be read because it is missing.") {}
        .background(SignuColor.paper)
}
