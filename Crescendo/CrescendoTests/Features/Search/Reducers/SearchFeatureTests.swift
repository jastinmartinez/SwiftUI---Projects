import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchFeatureTests {
    @Test
    func stateProviderSelectsExactlyOneBoundSearchClient() async {
        let song = makeTrack()
        let page = SearchPage(
            tracks: [song],
            nextCursor: SearchCursor(value: "next")
        )
        let testProviderSearchCount = LockIsolated(0)
        let jamendoSearchCount = LockIsolated(0)
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let store = TestStore(
            initialState: makeState(
                query: "result",
                status: .idle,
                providerAccess: access,
                providerID: .jamendo
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { _, _ in
                            testProviderSearchCount.withValue { $0 += 1 }
                            return SearchPage(tracks: [], nextCursor: nil)
                        }
                    ),
                    .jamendo: ProviderSearchClient(
                        searchPage: { request, limit in
                            jamendoSearchCount.withValue { $0 += 1 }
                            #expect(request == .initial(query: "result"))
                            #expect(limit == 20)
                            return page
                        }
                    ),
                ]
            )
        }

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(
                providerID: .jamendo,
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
                paginationStatus: .idle,
                providerID: .jamendo
            )
        }

        #expect(testProviderSearchCount.value == 0)
        #expect(jamendoSearchCount.value == 1)
    }

    @Test
    func missingSearchRegistrationFailsClosedWithoutUsingAnotherProvider() async {
        let testProviderSearchCount = LockIsolated(0)
        let store = TestStore(
            initialState: makeState(
                query: "result",
                status: .idle,
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                ),
                providerID: .jamendo
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { _, _ in
                            testProviderSearchCount.withValue { $0 += 1 }
                            return SearchPage(tracks: [], nextCursor: nil)
                        }
                    )
                ]
            )
        }

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(
                providerID: .jamendo,
                query: "result",
                requestID: UUID(0)
            )
        ) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.receive(
            .searchResponse(UUID(0), .failure(.providerUnavailable(.jamendo)))
        ) {
            $0.status = .failed(.providerUnavailable(.jamendo))
        }

        #expect(testProviderSearchCount.value == 0)
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
                providerAccess: access,
                providerID: .testProvider
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, _ in
                            #expect(request == .initial(query: "result"))
                            return page
                        }
                    )
                ]
            )
        }

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(
                providerID: .testProvider,
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
                paginationStatus: .idle,
                providerID: .testProvider
            )
        }

        #expect(store.state.providerAccess == access)
    }

    @Test(arguments: [
        Optional<MusicProviderAccess>.none,
        MusicProviderAccess(
            authorization: .denied,
            playbackEligibility: .unknown
        ),
    ])
    func submitDoesNotRequireProviderAccess(
        providerAccess: MusicProviderAccess?
    ) async {
        let page = SearchPage(tracks: [makeTrack()], nextCursor: nil)
        let store = TestStore(
            initialState: makeState(
                query: "result",
                status: .idle,
                providerAccess: providerAccess,
                providerID: .testProvider
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, limit in
                            #expect(request == .initial(query: "result"))
                            #expect(limit == 20)
                            return page
                        }
                    )
                ]
            )
        }

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(
                providerID: .testProvider,
                query: "result",
                requestID: UUID(0)
            )
        ) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.receive(.searchResponse(UUID(0), .success(page))) {
            $0.status = loadedStatus(
                tracks: page.tracks,
                nextCursor: nil,
                paginationStatus: .idle,
                providerID: .testProvider
            )
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
                providerAccess: access,
                providerID: .testProvider
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, _ in
                            #expect(request == .initial(query: "old"))
                            return try await Task.never()
                        }
                    )
                ]
            )
        }

        await store.send(.submitButtonTapped)
        await store.receive(
            .startSearch(
                providerID: .testProvider,
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
                    paginationStatus: .idle,
                    providerID: .testProvider
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                ),
                providerID: .testProvider
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
                    paginationStatus: .idle,
                    providerID: .testProvider
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                ),
                providerID: .testProvider
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, _ in
                            let expectedRequest = SearchPageRequest.continuation(
                                SearchCursor(value: "page-2")
                            )
                            #expect(request == expectedRequest)
                            return try await Task.never()
                        }
                    )
                ]
            )
        }

        await store.send(.pagination(.nextPageRequested))
        await store.receive(
            .pagination(
                .continueSearch(
                    providerID: .testProvider,
                    cursor: SearchCursor(value: "page-2"),
                    requestID: UUID(0)
                )
            )
        ) {
            $0.status = loadedStatus(
                tracks: [song],
                nextCursor: SearchCursor(value: "page-2"),
                paginationStatus: .loading(requestID: UUID(0)),
                providerID: .testProvider
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
        providerAccess: MusicProviderAccess?,
        providerID: ProviderID
    ) -> SearchFeature.State {
        SearchFeature.State(
            query: query,
            status: status,
            providerAccess: providerAccess,
            providerID: providerID
        )
    }

    private func loadedStatus(
        tracks: [Track],
        nextCursor: SearchCursor?,
        paginationStatus: SearchPaginationFeature.Status,
        providerID: ProviderID
    ) -> SearchFeature.Status {
        .loaded(
            SearchPaginationFeature.State(
                tracks: .init(uniqueElements: tracks),
                nextCursor: nextCursor,
                status: paginationStatus,
                providerID: providerID
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
