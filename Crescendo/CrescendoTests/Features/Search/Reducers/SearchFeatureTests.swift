import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchFeatureTests {
    @Test
    func authorizedAccessSearchesImmediatelyWithoutRequestingAccess() async {
        let song = makeTrack()
        let page = SearchPage(
            tracks: [song],
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
            $0.providerSearch.searchPage = { providerID, request, limit in
                #expect(providerID == .appleMusic)
                #expect(request == .initial(query: "result"))
                #expect(limit == 20)
                return page
            }
        }

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(
                providerID: .appleMusic,
                query: "result",
                requestID: UUID(0)
            )
        ) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success(page))) {
            $0.status = loadedStatus(
                tracks: page.tracks,
                nextCursor: page.nextCursor,
                paginationStatus: .idle
            )
        }
    }

    @Test
    func ineligibleAuthorizedAccessStillSearchesAndIsRetained() async {
        let song = makeTrack()
        let page = SearchPage(tracks: [song], nextCursor: nil)
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
            $0.providerSearch.searchPage = { providerID, request, _ in
                #expect(providerID == .appleMusic)
                #expect(request == .initial(query: "result"))
                return page
            }
        }

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(
                providerID: .appleMusic,
                query: "result",
                requestID: UUID(0)
            )
        ) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success(page))) {
            $0.status = loadedStatus(
                tracks: page.tracks,
                nextCursor: page.nextCursor,
                paginationStatus: .idle
            )
        }

        #expect(store.state.providerAccess == access)
    }

    @Test
    func unresolvedAccessMakesSubmitATrueNoOp() async {
        let song = makeTrack()
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
                    tracks: [song],
                    nextCursor: nil,
                    paginationStatus: .idle
                ),
                providerAccess: providerAccess
            )
            let store = TestStore(initialState: state) {
                SearchFeature()
            } withDependencies: {
                $0.providerSearch.searchPage = { _, _, _ in
                    Issue.record("Search must not run without authorized access")
                    return SearchPage(tracks: [], nextCursor: nil)
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
            $0.providerSearch.searchPage = { providerID, request, _ in
                #expect(providerID == .appleMusic)
                #expect(request == .initial(query: "old"))
                return try await Task.never()
            }
        }

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(
                providerID: .appleMusic,
                query: "old",
                requestID: UUID(0)
            )
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
                .success(SearchPage(tracks: [makeTrack()], nextCursor: nil))
            )
        )
    }

    @Test
    func tappingLoadedResultDelegatesSongTap() async {
        let song = makeTrack()
        let secondSong = makeTrack(nativeID: "2")
        let store = TestStore(
            initialState: makeState(
                query: "result",
                status: loadedStatus(
                    tracks: [song, secondSong],
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
                .trackTapped(
                    song,
                    loadedResults: [song, secondSong]
                )
            )
        )
    }

    @Test
    func queryChangeCancelsAnUnresolvedContinuationRequest() async {
        let song = makeTrack()
        let store = TestStore(
            initialState: makeState(
                query: "old",
                status: loadedStatus(
                    tracks: [song],
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
            $0.providerSearch.searchPage = { providerID, request, _ in
                #expect(providerID == .appleMusic)
                let expectedRequest = SearchPageRequest.continuation(
                    SearchCursor(value: "page-2")
                )
                #expect(request == expectedRequest)
                return try await Task.never()
            }
        }

        await store.send(.pagination(.nextPageRequested))
        await store.receive(
            .pagination(
                .continueSearch(
                    providerID: .appleMusic,
                    cursor: SearchCursor(value: "page-2"),
                    requestID: UUID(0)
                )
            )
        ) {
            $0.status = loadedStatus(
                tracks: [song],
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
            providerAccess: providerAccess,
            providerID: .appleMusic
        )
    }

    private func loadedStatus(
        tracks: [Track],
        nextCursor: SearchCursor?,
        paginationStatus: SearchPaginationFeature.Status
    ) -> SearchFeature.Status {
        .loaded(
            SearchPaginationFeature.State(
                tracks: .init(uniqueElements: tracks),
                nextCursor: nextCursor,
                status: paginationStatus,
                providerID: .appleMusic
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

    private func makeTrack(nativeID: String = "1") -> Track {
        Track(
            id: .init(providerID: "fake", nativeID: nativeID),
            title: "Result",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
    }
}
