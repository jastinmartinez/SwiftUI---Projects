import ComposableArchitecture

/// Exposes provider-qualified authorization and playback eligibility.
struct ProviderAccessClient: Sendable {
    var currentAccess: @Sendable (_ providerID: ProviderID) async -> MusicProviderAccess
    var requestAccess: @Sendable (_ providerID: ProviderID) async -> MusicProviderAccess
}

extension DependencyValues {
    var providerAccess: ProviderAccessClient {
        get { self[ProviderAccessClient.self] }
        set { self[ProviderAccessClient.self] = newValue }
    }
}
