/// Describes a registered provider and the music behavior it currently supports.
struct ProviderDescriptor: Equatable, Sendable {
    let id: ProviderID
    let name: String
    let musicCapabilities: MusicProviderCapabilities
}

extension ProviderDescriptor {
    /// The Jamendo provider registered by the application composition root.
    static let jamendo = Self(
        id: .jamendo,
        name: "Jamendo",
        musicCapabilities: .allEnabled
    )
}
