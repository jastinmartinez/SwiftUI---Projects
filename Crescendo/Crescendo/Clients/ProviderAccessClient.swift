import ComposableArchitecture

/// Exposes authorization and playback eligibility for one provider.
struct ProviderAccessClient: Sendable {
    var currentAccess: @Sendable () async -> MusicProviderAccess
    var requestAccess: @Sendable () async -> MusicProviderAccess
}

extension DependencyValues {
    var providerAccessClients: ProviderClientRegistry<ProviderAccessClient> {
        get { self[ProviderAccessClientsKey.self] }
        set { self[ProviderAccessClientsKey.self] = newValue }
    }
}

private enum ProviderAccessClientsKey: DependencyKey {
    static let liveValue = ProviderClientRegistry<ProviderAccessClient>(
        clients: [:]
    )
}
