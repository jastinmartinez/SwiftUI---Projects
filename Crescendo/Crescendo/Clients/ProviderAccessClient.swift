import ComposableArchitecture

/// Exposes provider authorization and playback-eligibility access.
struct ProviderAccessClient: Sendable {
    var currentAccess: @Sendable () async -> MusicProviderAccess
    var requestAccess: @Sendable () async -> MusicProviderAccess
}

extension DependencyValues {
    var providerAccess: ProviderAccessClient {
        get { self[ProviderAccessClient.self] }
        set { self[ProviderAccessClient.self] = newValue }
    }
}
