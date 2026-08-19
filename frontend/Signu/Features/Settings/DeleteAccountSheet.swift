import SwiftUI

struct DeleteAccountSheet: View {
    let scope: DeleteAccountScope
    var onDelete: () -> Void = {}

    @State private var typed = ""

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Delete your account?")
                    .font(.signuTitle)
                    .foregroundStyle(SignuColor.textPrimary)
                Text("This is permanent. There's no grace period and no undo.")
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                scopeLine("\(scope.bankCount) bank link\(scope.bankCount == 1 ? "" : "s") and their transactions")
                scopeLine("\(scope.subscriptionCount) subscriptions and every charge since \(scope.sinceText)")
                scopeLine("Your profile and sign-in methods")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SignuColor.sunken.opacity(0.6), in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                OverlineText("Type DELETE to confirm")
                TextField("", text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(SignuFont.font(18, .semibold))
                    .kerning(2)
                    .foregroundStyle(SignuColor.textPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(SignuColor.surfaceBright, in: RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SignuMetric.tileRadius, style: .continuous)
                            .strokeBorder(SignuColor.hairline, lineWidth: 1)
                    }
            }

            Button("Delete my account", action: onDelete)
                .buttonStyle(.signuDestructiveFilled)
                .disabled(!matches)
                .opacity(matches ? 1 : 0.5)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SignuColor.paper)
    }

    private func scopeLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(SignuColor.red).frame(width: 7, height: 7).padding(.top, 7)
            Text(text)
                .font(.signuBody)
                .foregroundStyle(SignuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Delete account sheet (14a)") {
    SignuColor.paper.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            DeleteAccountSheet(scope: DeleteAccountScope(bankCount: 3, subscriptionCount: 14, sinceText: "Nov 23"))
                .presentationDetents([.height(520)])
        }
}
