/// Describes a registered provider and the music behavior it currently supports.
struct ProviderDescriptor: Equatable, Sendable {
    let id: ProviderID
    let name: String
    let musicCapabilities: MusicProviderCapabilities
}

extension ProviderDescriptor {
    /// The Apple Music provider registered by the application composition root.
    static let appleMusic = Self(
        id: .appleMusic,
        name: "Apple Music",
        musicCapabilities: .allEnabled
    )
}
