import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchFeatureTests {
    @Test
    func authorizedAccessSearchesImmediatelyWithoutRequestingAccess() async {
        let song = makeSong()
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let store = TestStore(
            initialState: makeState(
                query: "result",
                phase: .idle,
                providerAccess: access
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = {
                Issue.record("Search must not read current access")
                return access
            }
            $0.musicProvider.requestAccess = {
                Issue.record("Search must not request access")
                return access
            }
            $0.musicProvider.search = { _, _ in [song] }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success([song]))) {
            $0.phase = .loaded([song])
        }
    }

    @Test
    func ineligibleAuthorizedAccessStillSearchesAndIsRetained() async {
        let song = makeSong()
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .ineligible
        )
        let store = TestStore(
            initialState: makeState(
                query: "result",
                phase: .idle,
                providerAccess: access
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.search = { _, _ in [song] }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success([song]))) {
            $0.phase = .loaded([song])
        }

        #expect(store.state.providerAccess == access)
    }

    @Test
    func unresolvedAccessMakesSubmitATrueNoOp() async {
        let song = makeSong()
        let cases: [MusicProviderAccess?] = [
            nil,
            makeAccess(
                authorization: .denied,
                playbackEligibility: .unknown
            ),
        ]

        for providerAccess in cases {
            let state = makeState(
                query: "result",
                phase: .loaded([song]),
                providerAccess: providerAccess
            )
            let store = TestStore(initialState: state) {
                SearchFeature()
            } withDependencies: {
                $0.musicProvider.search = { _, _ in
                    Issue.record("Search must not run without authorized access")
                    return []
                }
            }

            await store.send(.submitButtonTapped)
            #expect(store.state == state)
        }
    }

    @Test
    func queryChangeCancelsInFlightSearchAndIgnoresStaleResponse() async {
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let store = TestStore(
            initialState: makeState(
                query: "old",
                phase: .idle,
                providerAccess: access
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.search = { _, _ in
                try await Task.never()
            }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0))
        }
        await store.send(.queryChanged("new")) {
            $0.query = "new"
            $0.phase = .idle
        }
        await store.send(.searchResponse(UUID(0), .success([makeSong()])))
    }

    @Test
    func tappingLoadedResultDelegatesSelectedSong() async {
        let song = makeSong()
        let store = TestStore(
            initialState: makeState(
                query: "result",
                phase: .loaded([song]),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            )
        ) {
            SearchFeature()
        }

        await store.send(.resultTapped(song.id))
        await store.receive(.delegate(.songSelected(song)))
    }

    // MARK: - Helpers

    private func makeState(
        query: String,
        phase: SearchFeature.Phase,
        providerAccess: MusicProviderAccess?
    ) -> SearchFeature.State {
        SearchFeature.State(
            query: query,
            phase: phase,
            providerAccess: providerAccess
        )
    }

    private func makeAccess(
        authorization: MusicAuthorizationStatus,
        playbackEligibility: CatalogPlaybackEligibility
    ) -> MusicProviderAccess {
        MusicProviderAccess(
            authorization: authorization,
            playbackEligibility: playbackEligibility
        )
    }

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Result",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
