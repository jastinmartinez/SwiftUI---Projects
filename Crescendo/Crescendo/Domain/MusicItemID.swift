/// Identifies an item by both its provider and provider-native identifier.
///
/// Native identifiers are not assumed to be unique across providers.
struct MusicItemID: Hashable, Sendable {
    let providerID: MusicProviderID
    let nativeID: String
}
