/// Assembles the ordered provider-search identities and their clients.
///
/// Library is required and always first. Optional remote providers retain
/// deterministic product order when present. This value owns no provider
/// configuration, API construction, search state, or reducer behavior.
struct ProviderSearchComposition {
    let providerIDs: [ProviderID]
    let clients: ProviderClientRegistry<ProviderSearchClient>

    init(
        library: ProviderSearchClient,
        jamendo: ProviderSearchClient?,
        audius: ProviderSearchClient?
    ) {
        var providerIDs: [ProviderID] = [.library]
        var clients: [ProviderID: ProviderSearchClient] = [
            .library: library
        ]

        if let jamendo {
            providerIDs.append(.jamendo)
            clients[.jamendo] = jamendo
        }
        if let audius {
            providerIDs.append(.audius)
            clients[.audius] = audius
        }

        self.providerIDs = providerIDs
        self.clients = ProviderClientRegistry(clients: clients)
    }
}
