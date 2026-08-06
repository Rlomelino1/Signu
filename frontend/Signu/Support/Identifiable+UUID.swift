import Foundation

/// Lets a `UUID?` drive `.sheet(item:)` / `.fullScreenCover(item:)` directly.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
