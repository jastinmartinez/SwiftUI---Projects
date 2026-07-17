import Foundation

/// Describes the provider currently being connected or used by the application.
enum ProviderConnection: Equatable, Sendable {
    case disconnected
    case connecting(providerID: ProviderID, requestID: UUID)
    case connected(providerID: ProviderID, access: MusicProviderAccess)
    case denied(providerID: ProviderID)
    case restricted(providerID: ProviderID)
    case failed(providerID: ProviderID)

    var providerID: ProviderID? {
        switch self {
        case .disconnected:
            nil
        case .connecting(let providerID, _),
            .connected(let providerID, _),
            .denied(let providerID),
            .restricted(let providerID),
            .failed(let providerID):
            providerID
        }
    }

    var access: MusicProviderAccess? {
        guard case .connected(_, let access) = self else { return nil }
        return access
    }
}
