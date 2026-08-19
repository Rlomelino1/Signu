import PhotosUI
import SwiftUI

struct EditProfileSheet: View {
    let provider: SignuDataProviding
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var profile: Profile?

    var body: some View {
        Group {
            if let profile {
                EditProfileView(
                    currentName: profile.displayName,
                    nameIsFallback: profile.displayNameIsFallback,
                    avatarPath: profile.avatarPath,
                    initial: initial(for: profile),
                    onSaveName: { name in
                        await write { try await provider.setDisplayName(name) }
                    },
                    onPickPhoto: { jpeg in
                        await write { try await provider.setAvatar(jpeg: jpeg) }
                    },
                    onRemovePhoto: {
                        await write { try await provider.removeAvatar() }
                    },
                    onClose: { dismiss() }
                )
            } else {
                Color.clear
            }
        }
        .task { profile = try? await provider.profile() }
    }

    private func initial(for profile: Profile) -> String {
        let source = profile.displayNameIsFallback ? profile.email : profile.displayName
        return String(source.prefix(1)).uppercased()
    }

    private func write(_ body: () async throws -> Void) async -> Bool {
        do {
            try await body()
            profile = try? await provider.profile()
            onChanged()
            return true
        } catch {
            return false
        }
    }
}

struct EditProfileView: View {
    let currentName: String
    let nameIsFallback: Bool
    let avatarPath: String?
    let initial: String

    var onSaveName: (String?) async -> Bool
    var onPickPhoto: (Data) async -> Bool
    var onRemovePhoto: () async -> Bool
    var onClose: () -> Void = {}

    @State private var name: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var busy: Busy?
    @State private var failure: String?
    @FocusState private var nameFocused: Bool

    private enum Busy { case name, photo, removal }

    private var trimmed: String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var nameChanged: Bool {
        if nameIsFallback { return trimmed != nil }
        return trimmed != currentName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Your profile")
                    .font(.signuSection)
                    .foregroundStyle(SignuColor.textPrimary)
                Spacer()
                Button("Done", action: onClose)
                    .font(.signuBody)
                    .foregroundStyle(SignuColor.textSecondary)
            }

            photoBlock
            nameBlock

            if let failure {
                Text(failure)
                    .font(SignuFont.font(13))
                    .foregroundStyle(SignuColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(SignuMetric.screenPadding)
        .background(SignuColor.paper)
        .onAppear { name = nameIsFallback ? "" : currentName }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await adopt(item) }
        }
    }


    private var photoBlock: some View {
        HStack(spacing: 16) {
            ProfileAvatar(path: avatarPath, initial: initial, size: 72)
                .overlay {
                    if busy == .photo || busy == .removal {
                        Circle().fill(SignuColor.ink.opacity(0.55))
                            .overlay { ProgressView().tint(SignuColor.onInk) }
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                PhotosPicker(
                    selection: $photoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text(avatarPath == nil ? "Add a photo" : "Change photo")
                        .font(.signuBody)
                        .foregroundStyle(SignuColor.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(SignuColor.surface, in: Capsule())
                }
                .disabled(busy != nil)

                if avatarPath != nil {
                    Button("Remove photo") {
                        Task { await remove() }
                    }
                    .font(SignuFont.font(13))
                    .foregroundStyle(SignuColor.red)
                    .disabled(busy != nil)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func adopt(_ item: PhotosPickerItem) async {
        busy = .photo
        failure = nil
        defer { busy = nil; photoItem = nil }

        guard let raw = try? await item.loadTransferable(type: Data.self),
              let picked = UIImage(data: raw) else {
            failure = "That photo could not be read. Try another one."
            return
        }
        guard let jpeg = AvatarImage.jpeg(from: picked) else {
            failure = "That photo could not be prepared. Try another one."
            return
        }
        if await onPickPhoto(jpeg) == false {
            failure = "The photo did not upload. Your name and everything else is unchanged."
        }
    }

    private func remove() async {
        busy = .removal
        failure = nil
        defer { busy = nil }
        if await onRemovePhoto() == false {
            failure = "The photo could not be removed."
        }
    }


    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverlineText("Name")
            TextField("How Signu should greet you", text: $name)
                .font(.signuBody)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(SignuColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onSubmit { Task { await saveName() } }

            Text(nameIsFallback
                 ? "Without a name, Signu greets you by the time of day and shows your email address here."
                 : "Clearing this puts your email address back.")
                .font(SignuFont.font(13))
                .foregroundStyle(SignuColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await saveName() }
            } label: {
                HStack(spacing: 8) {
                    if busy == .name { ProgressView().tint(SignuColor.onInk) }
                    Text("Save name")
                }
                .font(.signuBody)
                .foregroundStyle(SignuColor.onInk)
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(SignuColor.ink, in: Capsule())
            }
            .disabled(!nameChanged || busy != nil)
            .opacity(nameChanged && busy == nil ? 1 : 0.45)
        }
    }

    private func saveName() async {
        guard nameChanged else { return }
        busy = .name
        failure = nil
        nameFocused = false
        defer { busy = nil }
        if await onSaveName(trimmed) == false {
            failure = "That name could not be saved."
        }
    }
}

#if DEBUG
#Preview("Edit profile · no name yet") {
    EditProfileView(
        currentName: "you@example.com",
        nameIsFallback: true,
        avatarPath: nil,
        initial: "R",
        onSaveName: { _ in true },
        onPickPhoto: { _ in true },
        onRemovePhoto: { true }
    )
}

#Preview("Edit profile · named") {
    EditProfileView(
        currentName: "Alex Rivera",
        nameIsFallback: false,
        avatarPath: nil,
        initial: "R",
        onSaveName: { _ in true },
        onPickPhoto: { _ in true },
        onRemovePhoto: { true }
    )
}
#endif
