import SwiftUI

struct SearchScreen: View {
    let provider: SignuDataProviding
    var onSelectSubscription: (UUID) -> Void = { _ in }
    var onReviewSuggestion: (UUID) -> Void = { _ in }
    var onBack: () -> Void = {}
    var onLoadFailed: (String) -> Void = { _ in }

    @State private var payload: SubsPayload?
    @State private var failure: String?
    @State private var query = ""
    @FocusState private var focused: Bool

    private func load() async {
        do {
            payload = try await provider.subsPayload()
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

    private var results: [SearchRow] {
        guard let payload else { return [] }
        let all = SearchRow.rows(from: payload)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ChromeButton(systemName: "chevron.left", action: onBack)
                field
            }
            .padding(.top, 4)

            if let failure, payload == nil {
                LoadFailureView(message: failure) { await load() }
            } else if results.isEmpty {
                Text(query.isEmpty ? "Nothing to search yet." : "No subscription matches “\(query)”.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
                    .padding(.top, 6)
                Spacer()
            } else {
                ScrollView {
                    SignuListCard(data: results) { row in
                        Button {
                            if row.isSuggestion { onReviewSuggestion(row.id) }
                            else { onSelectSubscription(row.id) }
                        } label: {
                            SignuRow(
                                title: row.name,
                                subtitle: Text(row.subtitle),
                                trailingTitle: row.amountText.map { Text($0) }
                            ) {
                                ServiceAvatar(name: row.name)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, SignuMetric.scrollBottomInset)
                }
            }
        }
        .padding(.horizontal, SignuMetric.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignuColor.paper)
        .task {
            if payload == nil { await load() }
            focused = true
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SignuColor.textTertiary)
            TextField("Search subscriptions", text: $query)
                .font(.signuBody)
                .foregroundStyle(SignuColor.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(SignuColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(SignuColor.surface, in: Capsule())
    }
}

struct SearchRow: Identifiable {
    let id: UUID
    var name: String
    var subtitle: String
    var amountText: String?
    var isSuggestion: Bool

    static func rows(from payload: SubsPayload) -> [SearchRow] {
        let active = (payload.monthly.rows + payload.annual.rows).map { row in
            SearchRow(
                id: row.id,
                name: row.serviceName,
                subtitle: row.overdueDays.map { "Overdue · \($0) days" } ?? row.subtitle,
                amountText: SignuFormat.brl(row.amount, approximate: row.approximate),
                isSuggestion: false
            )
        }
        let inactive = payload.inactive.map { item in
            SearchRow(
                id: item.id,
                name: item.serviceName,
                subtitle: item.cancelled ? "Cancelled" : "Ended",
                amountText: nil,
                isSuggestion: false
            )
        }
        let suggested = payload.suggested.map { item in
            SearchRow(
                id: item.subscriptionId,
                name: item.serviceName,
                subtitle: "Suggested · not tracked yet",
                amountText: nil,
                isSuggestion: true
            )
        }
        return (active + suggested + inactive).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

#Preview("Search") {
    SearchScreen(provider: MockDataProvider())
}
