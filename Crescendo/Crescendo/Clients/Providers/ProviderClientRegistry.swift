/// Routes a provider identity to the client bound to that provider.
///
/// A missing registration returns `nil` so callers fail closed rather than
/// falling back to another provider's implementation.
struct ProviderClientRegistry<Client>: Sendable where Client: Sendable {
    let clients: [ProviderID: Client]

    subscript(providerID: ProviderID) -> Client? {
        clients[providerID]
    }
}
