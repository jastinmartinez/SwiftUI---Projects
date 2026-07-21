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
                status: .idle,
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

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(query: "result", requestID: UUID(0))
        ) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success(page))) {
            $0.status = loadedStatus(
                songs: page.songs,
                nextCursor: page.nextCursor,
                paginationStatus: .idle
            )
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
                status: .idle,
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

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(query: "result", requestID: UUID(0))
        ) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success(page))) {
            $0.status = loadedStatus(
                songs: page.songs,
                nextCursor: page.nextCursor,
                paginationStatus: .idle
            )
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
                status: loadedStatus(
                    songs: [song],
                    nextCursor: nil,
                    paginationStatus: .idle
                ),
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
                status: .idle,
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

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(query: "old", requestID: UUID(0))
        ) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.send(.queryChanged("new")) {
            $0.query = "new"
        }
        await store.receive(.cancelSearch) {
            $0.status = .idle
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
        let secondSong = makeSong(nativeID: "2")
        let store = TestStore(
            initialState: makeState(
                query: "result",
                status: loadedStatus(
                    songs: [song, secondSong],
                    nextCursor: nil,
                    paginationStatus: .idle
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            )
        ) {
            SearchFeature()
        }

        await store.send(.resultTapped(song.id))
        await store.receive(
            .delegate(
                .songTapped(
                    song,
                    loadedResults: [song, secondSong]
                )
            )
        )
    }

    @Test
    func queryChangeCancelsAnUnresolvedContinuationRequest() async {
        let song = makeSong()
        let store = TestStore(
            initialState: makeState(
                query: "old",
                status: loadedStatus(
                    songs: [song],
                    nextCursor: SearchCursor(value: "page-2"),
                    paginationStatus: .idle
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearch.search = { _, _ in
                Issue.record("Pagination must not start a new search")
                return SearchPage(songs: [], nextCursor: nil)
            }
            $0.providerSearch.nextSearchPage = { _, _ in
                try await Task.never()
            }
        }

        await store.send(.pagination(.nextPageRequested))
        await store.receive(
            .pagination(
                .startNextPage(
                    cursor: SearchCursor(value: "page-2"),
                    requestID: UUID(0)
                )
            )
        ) {
            $0.status = loadedStatus(
                songs: [song],
                nextCursor: SearchCursor(value: "page-2"),
                paginationStatus: .loading(requestID: UUID(0))
            )
        }
        await store.send(.queryChanged("new")) {
            $0.query = "new"
        }
        await store.receive(.cancelSearch) {
            $0.status = .idle
        }
    }

    // MARK: - Helpers

    private func makeState(
        query: String,
        status: SearchFeature.Status,
        providerAccess: MusicProviderAccess?
    ) -> SearchFeature.State {
        SearchFeature.State(
            query: query,
            status: status,
            providerAccess: providerAccess
        )
    }

    private func loadedStatus(
        songs: [SongSummary],
        nextCursor: SearchCursor?,
        paginationStatus: SearchPaginationFeature.Status
    ) -> SearchFeature.Status {
        .loaded(
            SearchPaginationFeature.State(
                songs: .init(uniqueElements: songs),
                nextCursor: nextCursor,
                status: paginationStatus
            )
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

    private func makeSong(nativeID: String = "1") -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: nativeID),
            title: "Result",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
