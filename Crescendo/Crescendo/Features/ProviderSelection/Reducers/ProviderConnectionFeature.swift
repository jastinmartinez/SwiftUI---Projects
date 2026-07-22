import ComposableArchitecture
import Foundation
import UIKit

/// Owns registered providers and the lifecycle of connecting to one provider.
@Reducer
struct ProviderConnectionFeature {
    @ObservableState
    struct State: Equatable {
        let providers: [ProviderDescriptor]
        var connection: ProviderConnection
    }

    /// Events that require coordination with sibling application features.
    enum Delegate: Equatable {
        case connectionStarted(
            providerID: ProviderID,
            providerChanged: Bool
        )
        case connectionResolved(ProviderConnection)
    }

    enum Action: Equatable {
        case connect(ProviderID)
        case startConnection(ProviderID)
        case retryButtonTapped
        case openSettingsButtonTapped
        case currentAccessResponse(
            requestID: UUID,
            providerID: ProviderID,
            access: MusicProviderAccess
        )
        case requestedAccessResponse(
            requestID: UUID,
            providerID: ProviderID,
            access: MusicProviderAccess
        )
        case accessResolved(
            requestID: UUID,
            providerID: ProviderID,
            access: MusicProviderAccess
        )
        case delegate(Delegate)
    }

    enum CancelID {
        case access
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.providerAccess) var providerAccess
    @Dependency(\.openURL) var openURL

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .connect(let providerID):
                guard state.provider(id: providerID) != nil else {
                    return .none
                }
                return .send(.startConnection(providerID))

            case .startConnection(let providerID):
                guard let provider = state.provider(id: providerID) else {
                    return .none
                }
                let previousProviderID = state.connection.providerID
                let requestID = uuid()

                state.connection = .connecting(
                    providerID: provider.id,
                    requestID: requestID
                )

                return .concatenate(
                    .send(
                        .delegate(
                            .connectionStarted(
                                providerID: provider.id,
                                providerChanged: previousProviderID != provider.id
                            )
                        )
                    ),
                    .run { send in
                        let access = await providerAccess.currentAccess()
                        await send(
                            .currentAccessResponse(
                                requestID: requestID,
                                providerID: provider.id,
                                access: access
                            )
                        )
                    }
                )
                .cancellable(id: CancelID.access, cancelInFlight: true)

            case .retryButtonTapped:
                guard case .failed(let providerID) = state.connection,
                    state.provider(id: providerID) != nil
                else {
                    return .none
                }
                return .send(.startConnection(providerID))

            case .openSettingsButtonTapped:
                return .run { _ in
                    let settingsURL = UIApplication.openSettingsURLString
                    guard let url = URL(string: settingsURL) else { return }
                    await openURL(url)
                }

            case .currentAccessResponse(
                let requestID,
                let providerID,
                let access
            ):
                let expectedConnection = ProviderConnection.connecting(
                    providerID: providerID,
                    requestID: requestID
                )
                guard state.connection == expectedConnection else {
                    return .none
                }

                guard access.authorization == .notDetermined else {
                    return .send(
                        .accessResolved(
                            requestID: requestID,
                            providerID: providerID,
                            access: access
                        )
                    )
                }

                return .run { send in
                    let requestedAccess = await providerAccess.requestAccess()
                    await send(
                        .requestedAccessResponse(
                            requestID: requestID,
                            providerID: providerID,
                            access: requestedAccess
                        )
                    )
                }
                .cancellable(id: CancelID.access)

            case .requestedAccessResponse(
                let requestID,
                let providerID,
                let access
            ):
                let expectedConnection = ProviderConnection.connecting(
                    providerID: providerID,
                    requestID: requestID
                )
                guard state.connection == expectedConnection else {
                    return .none
                }
                return .send(
                    .accessResolved(
                        requestID: requestID,
                        providerID: providerID,
                        access: access
                    )
                )

            case .accessResolved(let requestID, let providerID, let access):
                let expectedConnection = ProviderConnection.connecting(
                    providerID: providerID,
                    requestID: requestID
                )
                guard state.connection == expectedConnection else {
                    return .none
                }

                let connection: ProviderConnection

                switch access.authorization {
                case .authorized:
                    connection = .connected(
                        providerID: providerID,
                        access: access
                    )
                case .denied:
                    connection = .denied(providerID: providerID)
                case .restricted:
                    connection = .restricted(providerID: providerID)
                case .notDetermined:
                    connection = .failed(providerID: providerID)
                }

                state.connection = connection
                return .send(.delegate(.connectionResolved(connection)))

            case .delegate:
                return .none
            }
        }
    }
}

extension ProviderConnectionFeature.State {
    var activeProvider: ProviderDescriptor? {
        providers.first { $0.id == connection.providerID }
    }

    func provider(id: ProviderID) -> ProviderDescriptor? {
        providers.first { $0.id == id }
    }
}
