import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchFeatureTests {
    @Test
    func authorizedAccessSearchesImmediatelyWithoutRequestingAccess() async {
        let song = makeSong()
        let page = SearchPage(
            songs: [song],
            nextCursor: SearchCursor(value: "next")
        )
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
            $0.providerSearch.search = { query, limit in
                #expect(query == "result")
                #expect(limit == 20)
                return page
            }
            $0.providerSearch.nextSearchPage = { _, _ in
                Issue.record("The initial search must not request a continuation page")
                return SearchPage(songs: [], nextCursor: nil)
            }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success(page))) {
            $0.phase = .loaded([song])
        }
    }

    @Test
    func ineligibleAuthorizedAccessStillSearchesAndIsRetained() async {
        let song = makeSong()
        let page = SearchPage(songs: [song], nextCursor: nil)
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
            $0.providerSearch.search = { _, _ in page }
            $0.providerSearch.nextSearchPage = { _, _ in
                Issue.record("The initial search must not request a continuation page")
                return SearchPage(songs: [], nextCursor: nil)
            }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success(page))) {
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
                $0.providerSearch.search = { _, _ in
                    Issue.record("Search must not run without authorized access")
                    return SearchPage(songs: [], nextCursor: nil)
                }
                $0.providerSearch.nextSearchPage = { _, _ in
                    Issue.record("Pagination must not run without authorized access")
                    return SearchPage(songs: [], nextCursor: nil)
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
            $0.providerSearch.search = { _, _ in
                try await Task.never()
            }
            $0.providerSearch.nextSearchPage = { _, _ in
                Issue.record("The initial search must not request a continuation page")
                return SearchPage(songs: [], nextCursor: nil)
            }
        }

        await store.send(.submitButtonTapped) {
            $0.phase = .loading(requestID: UUID(0))
        }
        await store.send(.queryChanged("new")) {
            $0.query = "new"
            $0.phase = .idle
        }
        await store.send(
            .searchResponse(
                UUID(0),
                .success(SearchPage(songs: [makeSong()], nextCursor: nil))
            )
        )
    }

    @Test
    func tappingLoadedResultDelegatesSongTap() async {
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
        await store.receive(.delegate(.songTapped(song)))
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
