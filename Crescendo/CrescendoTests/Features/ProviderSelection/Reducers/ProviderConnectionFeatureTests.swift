import ComposableArchitecture
import Foundation
import Testing
import UIKit

@testable import Crescendo

@MainActor
struct ProviderConnectionFeatureTests {
    @Test
    func authorizedCurrentAccessConnectsWithoutRequestingPermission() async {
        let currentAccessCount = LockIsolated(0)
        let requestAccessCount = LockIsolated(0)
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let store = makeStore(
            currentAccess: {
                currentAccessCount.withValue { $0 += 1 }
                return access
            },
            requestAccess: {
                requestAccessCount.withValue { $0 += 1 }
                return access
            }
        )

        await store.send(.connect(.appleMusic))
        await store.receive(.startConnection(.appleMusic)) {
            $0.connection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .delegate(
                .connectionStarted(
                    providerID: .appleMusic,
                    providerChanged: true
                )
            )
        )
        await store.receive(
            .currentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        )
        await store.receive(
            .accessResolved(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        ) {
            $0.connection = .connected(
                providerID: .appleMusic,
                access: access
            )
        }
        await store.receive(
            .delegate(
                .connectionResolved(
                    .connected(
                        providerID: .appleMusic,
                        access: access
                    )
                )
            )
        )

        #expect(currentAccessCount.value == 1)
        #expect(requestAccessCount.value == 0)
    }

    @Test
    func undeterminedCurrentAccessRequestsPermission() async {
        let requestAccessCount = LockIsolated(0)
        let currentAccess = makeAccess(authorization: .notDetermined)
        let requestedAccess = makeAccess(
            authorization: .authorized,
            playbackEligibility: .ineligible
        )
        let store = makeStore(
            currentAccess: { currentAccess },
            requestAccess: {
                requestAccessCount.withValue { $0 += 1 }
                return requestedAccess
            }
        )

        await store.send(.connect(.appleMusic))
        await store.receive(.startConnection(.appleMusic)) {
            $0.connection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .delegate(
                .connectionStarted(
                    providerID: .appleMusic,
                    providerChanged: true
                )
            )
        )
        await store.receive(
            .currentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: currentAccess
            )
        )
        await store.receive(
            .requestedAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: requestedAccess
            )
        )
        await store.receive(
            .accessResolved(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: requestedAccess
            )
        ) {
            $0.connection = .connected(
                providerID: .appleMusic,
                access: requestedAccess
            )
        }
        await store.receive(
            .delegate(
                .connectionResolved(
                    .connected(
                        providerID: .appleMusic,
                        access: requestedAccess
                    )
                )
            )
        )

        #expect(requestAccessCount.value == 1)
    }

    @Test(arguments: [
        (
            MusicAuthorizationStatus.denied,
            ProviderConnection.denied(providerID: .appleMusic)
        ),
        (
            MusicAuthorizationStatus.restricted,
            ProviderConnection.restricted(providerID: .appleMusic)
        ),
    ])
    func currentAccessMapsUnavailableAuthorization(
        authorization: MusicAuthorizationStatus,
        expectedConnection: ProviderConnection
    ) async {
        let access = makeAccess(authorization: authorization)
        let store = makeStore(currentAccess: { access })

        await store.send(.connect(.appleMusic))
        await store.receive(.startConnection(.appleMusic)) {
            $0.connection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .delegate(
                .connectionStarted(
                    providerID: .appleMusic,
                    providerChanged: true
                )
            )
        )
        await store.receive(
            .currentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        )
        await store.receive(
            .accessResolved(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        ) {
            $0.connection = expectedConnection
        }
        await store.receive(
            .delegate(.connectionResolved(expectedConnection))
        )
    }

    @Test
    func secondUndeterminedResponseFailsConnection() async {
        let access = makeAccess(authorization: .notDetermined)
        let expectedConnection = ProviderConnection.failed(
            providerID: .appleMusic
        )
        let store = makeStore(
            currentAccess: { access },
            requestAccess: { access }
        )

        await store.send(.connect(.appleMusic))
        await store.receive(.startConnection(.appleMusic)) {
            $0.connection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .delegate(
                .connectionStarted(
                    providerID: .appleMusic,
                    providerChanged: true
                )
            )
        )
        await store.receive(
            .currentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        )
        await store.receive(
            .requestedAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        )
        await store.receive(
            .accessResolved(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        ) {
            $0.connection = expectedConnection
        }
        await store.receive(
            .delegate(.connectionResolved(expectedConnection))
        )
    }

    @Test
    func retryCreatesFreshRequestAndIgnoresStaleResponse() async {
        let access = makeAccess(authorization: .authorized)
        let (resumeAccess, resumeAccessContinuation) =
            AsyncStream<Void>.makeStream()
        let store = makeStore(
            connection: .failed(providerID: .appleMusic),
            currentAccess: {
                for await _ in resumeAccess { break }
                return access
            }
        )

        await store.send(.retryButtonTapped)
        await store.receive(.startConnection(.appleMusic)) {
            $0.connection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .delegate(
                .connectionStarted(
                    providerID: .appleMusic,
                    providerChanged: false
                )
            )
        )
        await store.send(
            .currentAccessResponse(
                requestID: UUID(99),
                providerID: .appleMusic,
                access: access
            )
        )

        resumeAccessContinuation.yield()
        resumeAccessContinuation.finish()
        await store.receive(
            .currentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        )
        await store.receive(
            .accessResolved(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        ) {
            $0.connection = .connected(
                providerID: .appleMusic,
                access: access
            )
        }
        await store.receive(
            .delegate(
                .connectionResolved(
                    .connected(
                        providerID: .appleMusic,
                        access: access
                    )
                )
            )
        )
    }

    @Test
    func staleAccessActionsCannotResolveCurrentConnection() async {
        let state = ProviderConnectionFeature.State(
            providers: [.appleMusic],
            connection: .connecting(
                providerID: .appleMusic,
                requestID: UUID(1)
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .requestedAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: makeAccess(authorization: .authorized)
            )
        )
        await store.send(
            .accessResolved(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: makeAccess(authorization: .authorized)
            )
        )

        #expect(store.state == state)
    }

    @Test
    func unavailableProviderAndInvalidRetryAreNoOps() async {
        let state = ProviderConnectionFeature.State(
            providers: [],
            connection: .disconnected
        )
        let store = makeStore(state: state)

        await store.send(.connect("missing"))
        await store.send(.startConnection("missing"))
        await store.send(.retryButtonTapped)

        #expect(store.state == state)
    }

    @Test
    func activeProviderUsesConnectionIdentity() {
        let access = makeAccess(authorization: .authorized)
        var state = ProviderConnectionFeature.State(
            providers: [.appleMusic],
            connection: .connected(
                providerID: .appleMusic,
                access: access
            )
        )

        #expect(state.activeProvider?.name == "Apple Music")
        #expect(state.provider(id: .appleMusic)?.id == .appleMusic)

        state.connection = .disconnected
        #expect(state.activeProvider == nil)
        #expect(state.provider(id: "missing") == nil)
    }

    @Test
    func openSettingsUsesSystemSettingsURL() async {
        let openedURLs = LockIsolated<[URL]>([])
        let store = makeStore(
            configureDependencies: {
                $0.openURL = OpenURLEffect { url in
                    openedURLs.withValue { $0.append(url) }
                    return true
                }
            }
        )

        await store.send(.openSettingsButtonTapped)

        #expect(
            openedURLs.value
                == [URL(string: UIApplication.openSettingsURLString)]
        )
    }

    // MARK: - Helpers

    private func makeStore(
        connection: ProviderConnection = .disconnected,
        currentAccess: @escaping @Sendable () async -> MusicProviderAccess = {
            MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .unknown
            )
        },
        requestAccess: @escaping @Sendable () async -> MusicProviderAccess = {
            MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .unknown
            )
        },
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ProviderConnectionFeature> {
        makeStore(
            state: ProviderConnectionFeature.State(
                providers: [.appleMusic],
                connection: connection
            ),
            currentAccess: currentAccess,
            requestAccess: requestAccess,
            configureDependencies: configureDependencies
        )
    }

    private func makeStore(
        state: ProviderConnectionFeature.State,
        currentAccess: @escaping @Sendable () async -> MusicProviderAccess = {
            MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .unknown
            )
        },
        requestAccess: @escaping @Sendable () async -> MusicProviderAccess = {
            MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .unknown
            )
        },
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ProviderConnectionFeature> {
        TestStore(initialState: state) {
            ProviderConnectionFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = currentAccess
            $0.musicProvider.requestAccess = requestAccess
            configureDependencies(&$0)
        }
    }

    private func makeAccess(
        authorization: MusicAuthorizationStatus,
        playbackEligibility: CatalogPlaybackEligibility = .unknown
    ) -> MusicProviderAccess {
        MusicProviderAccess(
            authorization: authorization,
            playbackEligibility: playbackEligibility
        )
    }
}
