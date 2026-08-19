import SwiftUI

struct ServiceAvatar: View {
    let name: String
    var size: CGFloat = 44
    var color: Color?
    var onInk = false
    var kind: BrandKind = .service

    @Environment(LogoStore.self) private var logos: LogoStore?

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1))
    }

    var body: some View {
        if let logo = logos?.image(forName: name, kind: kind) {
            mark(logo)
        } else {
            monogram
        }
    }

    private func mark(_ logo: Image) -> some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(SignuColor.surfaceBright)
            .frame(width: size, height: size)
            .overlay {
                logo
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            }
            .overlay {
                if !onInk {
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .strokeBorder(SignuColor.hairline, lineWidth: 1)
                }
            }
    }

    private var monogram: some View {
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
