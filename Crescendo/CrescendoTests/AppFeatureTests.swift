import ComposableArchitecture
import Foundation
import Testing
import UIKit

@testable import Crescendo

@MainActor
struct AppFeatureTests {
    @Test
    func taskLeavesSoleProviderDisconnected() async {
        let store = makeStore()

        await store.send(.task)

        #expect(store.state.providerConnection == .disconnected)
        #expect(store.state.requiresProviderSelection)
    }

    @Test
    func selectingAuthorizedProviderUsesCurrentAccessWithoutRequestingPermission() async {
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

        await store.send(.providerSelected(.appleMusic)) {
            $0.providerConnection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .providerCurrentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        ) {
            $0.providerConnection = .connected(
                providerID: .appleMusic,
                access: access
            )
            $0.search.playbackEligibility = .eligible
        }

        #expect(currentAccessCount.value == 1)
        #expect(requestAccessCount.value == 0)
    }

    @Test
    func undeterminedAccessRequestsPermission() async {
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

        await store.send(.providerSelected(.appleMusic)) {
            $0.providerConnection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .providerCurrentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: currentAccess
            )
        )
        await store.receive(
            .providerRequestedAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: requestedAccess
            )
        ) {
            $0.providerConnection = .connected(
                providerID: .appleMusic,
                access: requestedAccess
            )
            $0.search.playbackEligibility = .ineligible
        }

        #expect(requestAccessCount.value == 1)
    }

    @Test(arguments: [
        (MusicAuthorizationStatus.denied, ProviderConnection.denied(providerID: .appleMusic)),
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

        await store.send(.providerSelected(.appleMusic)) {
            $0.providerConnection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .providerCurrentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        ) {
            $0.providerConnection = expectedConnection
        }
    }

    @Test
    func secondUndeterminedResponseFailsConnection() async {
        let access = makeAccess(authorization: .notDetermined)
        let store = makeStore(
            currentAccess: { access },
            requestAccess: { access }
        )

        await store.send(.providerSelected(.appleMusic)) {
            $0.providerConnection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .providerCurrentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        )
        await store.receive(
            .providerRequestedAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        ) {
            $0.providerConnection = .failed(providerID: .appleMusic)
        }
    }

    @Test
    func retryStartsFreshConnectionRequest() async {
        let access = makeAccess(authorization: .authorized)
        let (resumeAccess, resumeAccessContinuation) = AsyncStream<Void>.makeStream()
        let store = makeStore(
            providerConnection: .failed(providerID: .appleMusic),
            currentAccess: {
                for await _ in resumeAccess { break }
                return access
            }
        )

        await store.send(.providerRetryTapped) {
            $0.providerConnection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.send(
            .providerCurrentAccessResponse(
                requestID: UUID(99),
                providerID: .appleMusic,
                access: access
            )
        )

        resumeAccessContinuation.yield()
        resumeAccessContinuation.finish()
        await store.receive(
            .providerCurrentAccessResponse(
                requestID: UUID(0),
                providerID: .appleMusic,
                access: access
            )
        ) {
            $0.providerConnection = .connected(
                providerID: .appleMusic,
                access: access
            )
        }
    }

    @Test
    func unavailableProviderCannotBeSelected() async {
        let state = makeState(registeredProviders: [])
        let store = makeStore(state: state)

        await store.send(.providerSelected("missing"))

        #expect(store.state == state)
    }

    @Test
    func activeProviderUsesConnectionIdentity() {
        let access = makeAccess(authorization: .authorized)
        var state = makeState(
            providerConnection: .connected(
                providerID: .appleMusic,
                access: access
            )
        )

        #expect(state.activeProvider?.name == "Apple Music")

        state.providerConnection = .disconnected
        #expect(state.activeProvider == nil)
    }

    @Test
    func providerOpenSettingsUsesSystemSettingsURL() async {
        let openedURLs = LockIsolated<[URL]>([])
        let store = makeStore(
            configureDependencies: {
                $0.openURL = OpenURLEffect { url in
                    openedURLs.withValue { $0.append(url) }
                    return true
                }
            }
        )

        await store.send(.providerOpenSettingsTapped)

        #expect(
            openedURLs.value
                == [URL(string: UIApplication.openSettingsURLString)]
        )
    }

    // MARK: - Helpers

    private func makeStore(
        providerConnection: ProviderConnection = .disconnected,
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
    ) -> TestStoreOf<AppFeature> {
        makeStore(
            state: makeState(providerConnection: providerConnection),
            currentAccess: currentAccess,
            requestAccess: requestAccess,
            configureDependencies: configureDependencies
        )
    }

    private func makeStore(
        state: AppFeature.State,
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
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = currentAccess
            $0.musicProvider.requestAccess = requestAccess
            configureDependencies(&$0)
        }
    }

    private func makeState(
        registeredProviders: [ProviderDescriptor] = [.appleMusic],
        providerConnection: ProviderConnection = .disconnected
    ) -> AppFeature.State {
        AppFeature.State(
            registeredProviders: registeredProviders,
            providerConnection: providerConnection,
            search: SearchFeature.State(
                query: "",
                phase: .idle,
                playbackEligibility: .unknown
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: .allEnabled
            ),
            isPlayerPresented: false,
            pendingProviderID: nil,
            providerSwitchRequestID: nil,
            playbackTransition: nil
        )
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
