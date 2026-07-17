/// Describes a registered provider and the behavior it supports.
struct MusicProviderDescriptor: Equatable, Sendable {
    let id: MusicProviderID
    let name: String
    let capabilities: MusicProviderCapabilities
}

extension MusicProviderDescriptor {
    /// The Apple Music provider registered by the application composition root.
    static let appleMusic = Self(
        id: "apple-music",
        name: "Apple Music",
        capabilities: .allEnabled
    )
}
