import SwiftUI

enum LoadFailureRoute: Equatable {
    case replaceScreen
    case reportOnly

    static func of(hasPayload: Bool) -> LoadFailureRoute {
        hasPayload ? .reportOnly : .replaceScreen
    }
}

struct LoadFailureView: View {
    let message: String
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
