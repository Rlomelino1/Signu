import SwiftUI

/// Monogram tile — tier 3 of the logo sourcing contract (the zero-data
/// fallback, and the only tier built at this stage). Colored rounded square
/// with the service's initial.
struct ServiceAvatar: View {
    let name: String
    var size: CGFloat = 44
    var color: Color?

    // Verbatim first character — "iCloud+" keeps its lowercase "i" (21r).
    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1))
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(color ?? BrandPalette.color(for: name))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(SignuFont.font(size * 0.45, .semibold))
                    .foregroundStyle(.white)
            }
    }
}

#Preview("Service avatars") {
    HStack(spacing: 12) {
        ServiceAvatar(name: "Netflix")
        ServiceAvatar(name: "Spotify")
        ServiceAvatar(name: "iCloud+")
        ServiceAvatar(name: "Globoplay", size: 56)
        ServiceAvatar(name: "Unknown Service")
    }
    .padding()
    .background(SignuColor.paper)
}
