import SwiftUI

/// The detail screen's overflow actions — rename and category.
///
/// Both columns have been user-owned since Migration #1 (`subscription.nickname`
/// and `subscription.category` are two of the seven the client may write) and
/// neither had a way in: the ellipsis called a closure nobody supplied. These are
/// therefore plain column writes, not Edge Function actions, and the difference
/// is visible in how they fail — see the detail screen's alert.
///
/// No mockup; designed to the system, like the R4 interval sheet.

/// Rename writes `nickname`, never `service_name`.
///
/// The engine's name for a merchant stays the engine's, and `displayName` already
/// prefers a nickname when one exists — so clearing the field is a real action
/// rather than an omission: it drops the nickname and the engine's name shows
/// through again. That is why the field starts EMPTY with the engine's name as
/// its placeholder, instead of pre-filled with a value the user never chose:
/// pre-filling would make "clear it" indistinguishable from "delete my own name".
struct RenameSheet: View {
    let serviceName: String
    let nickname: String?
    var onSave: (String?) -> Void
    var onCancel: () -> Void = {}

    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rename")
                    .font(.signuTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                Text("Your own name for this subscription. Signu keeps calling it \(serviceName) internally, so detection still recognises the charges.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(serviceName, text: $text)
                .font(.signuBody)
                .foregroundStyle(SignuColor.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
                .onSubmit { save() }

            VStack(spacing: 10) {
                Button("Save name") { save() }
                    .buttonStyle(.signuPrimary)
                    .disabled(trimmed.isEmpty)
                if nickname != nil {
                    // Only offered when there is something to undo, so the sheet
                    // never advertises an action with nothing to act on.
                    Button("Use \(serviceName) again") { onSave(nil) }
                        .buttonStyle(.signuSecondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SignuColor.paper)
        .task {
            text = nickname ?? ""
            focused = true
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }
}

/// Category is seeded by detection and editable here.
///
/// The options are the categories already present in the user's own data plus
/// whatever they type — not a fixed taxonomy invented in the client. A hardcoded
/// list would be the app asserting what categories exist, and the engine is the
/// thing that seeds them.
struct CategorySheet: View {
    let serviceName: String
    let current: String?
    let known: [String]
    var onSave: (String?) -> Void

    @State private var text = ""

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                    .font(.signuTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                Text("How \(serviceName) is grouped.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            }

            if !known.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(known, id: \.self) { category in
                            Button { onSave(category) } label: {
                                HStack(spacing: 12) {
                                    Text(category)
                                        .font(.signuRowTitle)
                                        .foregroundStyle(SignuColor.textPrimary)
                                    Spacer()
                                    if category == current {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(SignuColor.ink)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if category != known.last {
                                Rectangle()
                                    .fill(SignuColor.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.cardRadius, style: .continuous))
                }
                .frame(maxHeight: 220)
            }

            HStack(spacing: 10) {
                TextField("New category", text: $text)
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
                Button("Add") { onSave(trimmed) }
                    .buttonStyle(SignuButtonStyle(kind: .primary, fullWidth: false))
                    .disabled(trimmed.isEmpty)
            }

            if current != nil {
                Button("Remove category") { onSave(nil) }
                    .buttonStyle(.signuSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SignuColor.paper)
    }
}

#Preview("Rename") {
    RenameSheet(serviceName: "Netflix", nickname: nil, onSave: { _ in })
}

#Preview("Category") {
    CategorySheet(
        serviceName: "Netflix",
        current: "Streaming",
        known: ["Streaming", "AI", "Shopping", "Transport"],
        onSave: { _ in }
    )
}
