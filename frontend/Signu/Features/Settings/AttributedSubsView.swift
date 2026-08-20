import SwiftUI

struct AttributedSubsScreen: View {
    let provider: SignuDataProviding
    let connectionId: UUID
    var onBack: () -> Void = {}
    var onLoadFailed: (String) -> Void = { _ in }

    @State private var payload: AttributedSubsPayload?
    @State private var failure: String?

    var body: some View {
        Group {
            if let payload {
                AttributedSubsView(payload: payload, onBack: onBack)
            } else if let failure {
                LoadFailureView(message: failure) { await load() }
            } else {
                Color.clear
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            payload = try await provider.attributedSubsPayload(connectionId: connectionId)
            failure = nil
        } catch {
            switch LoadFailureRoute.of(hasPayload: payload != nil) {
            case .replaceScreen:
                payload = nil
                failure = error.localizedDescription
            case .reportOnly:
                onLoadFailed(error.localizedDescription)
            }
        }
    }
}

struct AttributedSubsView: View {
    let payload: AttributedSubsPayload
    var onBack: () -> Void = {}
    var scrollAnchor: UnitPoint = .top

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { ChromeButton(systemName: "chevron.left", action: onBack); Spacer() }
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    ServiceAvatar(name: payload.institutionName, size: 40, kind: .institution)
                    Text("Via \(payload.institutionName)")
                        .font(.signuTitle)
                        .foregroundStyle(SignuColor.textPrimary)
                }
                Text(payload.headerLine)
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.textSecondary)
                    .padding(.top, -8)

                ForEach(payload.cardGroups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        OverlineText(group.header)
                        SignuListCard(data: group.rows) { row in rowView(row) }
                    }
                }

                if !payload.dismissed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        OverlineText("Dismissed · \(payload.dismissed.count)")
                        SignuListCard(data: payload.dismissed) { row in rowView(row) }
                    }
                }

                Text("Removing this bank link decides what happens to these.")
                    .font(.signuSubtitle)
                    .foregroundStyle(SignuColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, SignuMetric.screenPadding)
            .padding(.bottom, 40)
            .defaultScrollAnchor(scrollAnchor)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SignuColor.paper)
    }

    private func rowView(_ row: AttributedSubsPayload.Row) -> some View {
        HStack(spacing: 12) {
            ServiceAvatar(name: row.serviceName)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.serviceName)
                    .font(.signuRowTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                Text(row.statusLine)
                    .font(SignuFont.font(14))
                    .foregroundStyle(row.statusTone == .danger ? SignuColor.red : SignuColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if let amount = row.amountText {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(amount)
                        .font(.signuRowTitle)
                        .foregroundStyle(SignuColor.textPrimary)
                    if let unit = row.unit {
                        Text(unit)
                            .font(SignuFont.font(14))
                            .foregroundStyle(SignuColor.textSecondary)
                    }
                }
                .fixedSize()
            }
        }
        .padding(SignuMetric.rowPaddingH)
    }
}

#Preview("Attributed subs (13a)") {
    let provider = MockDataProvider()
    let itau = provider.connectionList.first { $0.institutionName == "Demo Bank" }!
    return AttributedSubsScreen(provider: provider, connectionId: itau.id)
}
