import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

/// Verifies the behavior owned by one provider's independent results destination.
///
/// These tests cover continuation, cancellation, stale-response rejection, and
/// selection snapshots. Shared-query coordination, provider activation, and App
/// routing belong to their respective parent reducers.
@MainActor
struct ProviderSearchResultsReducerTests {
    @Test
    func nextPageUsesOwnedProviderAndAppendsOnlyNewTracks() async {
        let first = makeTrack(nativeID: "1")
        let duplicate = makeTrack(nativeID: "1")
        let second = makeTrack(nativeID: "2")
        let cursor = SearchCursor(value: "page-2")
        let nextCursor = SearchCursor(value: "page-3")
        let page = SearchPage(
            tracks: [duplicate, second],
            nextCursor: nextCursor
        )
        let otherProviderSearchCount = LockIsolated(0)
        let jamendoSearchCount = LockIsolated(0)
        let store = TestStore(
            initialState: ProviderSearchResultsReducer.State(
                providerID: .jamendo,
                query: "frozen query",
                tracks: [first],
                nextCursor: cursor,
                status: .idle
            )
        ) {
            ProviderSearchResultsReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { _, _ in
                            otherProviderSearchCount.withValue { $0 += 1 }
                            return SearchPage(tracks: [], nextCursor: nil)
                        }
                    ),
                    .jamendo: ProviderSearchClient(
                        searchPage: { request, limit in
                            jamendoSearchCount.withValue { $0 += 1 }
                            #expect(request == .continuation(cursor))
                            #expect(limit == 20)
                            return page
                        }
                    ),
                ]
            )
        }

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(cursor, requestID: UUID(0))
        ) {
            $0.status = .loading(requestID: UUID(0))
        }
        await store.receive(
            .searchPageResponse(UUID(0), .success(page))
        ) {
            $0.tracks.append(second)
            $0.nextCursor = nextCursor
            $0.status = .idle
        }

        #expect(store.state.query == "frozen query")
        #expect(otherProviderSearchCount.value == 0)
        #expect(jamendoSearchCount.value == 1)
    }

    @Test
    func selectionDelegatesTrackAndEveryCurrentlyLoadedTrack() async {
        let first = makeTrack(nativeID: "1")
        let second = makeTrack(nativeID: "2")
        let tracks = IdentifiedArray(uniqueElements: [first, second])
        let store = makeStore(tracks: tracks)

        await store.send(.resultTapped(second.id))
        await store.receive(
            .delegate(
                .trackTapped(
                    second,
                    loadedTracks: tracks
                )
            )
        )
    }

    @Test
    func unknownSelectionDoesNotDelegate() async {
        let tracks = IdentifiedArray(uniqueElements: [makeTrack(nativeID: "1")])
        let store = makeStore(tracks: tracks)

        await store.send(
            .resultTapped(
                TrackID(providerID: .testProvider, nativeID: "missing")
            )
        )
    }

    @Test
    func missingSearchRegistrationFailsWithoutUsingAnotherProvider() async {
        let otherProviderSearchCount = LockIsolated(0)
        let cursor = SearchCursor(value: "page-2")
        let store = TestStore(
            initialState: ProviderSearchResultsReducer.State(
                providerID: .jamendo,
                query: "query",
                tracks: [],
                nextCursor: cursor,
                status: .idle
            )
        ) {
            ProviderSearchResultsReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { _, _ in
                            otherProviderSearchCount.withValue { $0 += 1 }
                            return SearchPage(tracks: [], nextCursor: nil)
                        }
                    )
                ]
            )
        }

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(cursor, requestID: UUID(0))
        ) {
            $0.status = .loading(requestID: UUID(0))
        }
        await store.receive(
            .searchPageResponse(
                UUID(0),
                .failure(.providerUnavailable(.jamendo))
            )
        ) {
            $0.status = .failed(.providerUnavailable(.jamendo))
        }

        #expect(otherProviderSearchCount.value == 0)
    }

    @Test
    func exhaustedSearchDoesNotRequestAnotherPage() async {
        let state = ProviderSearchResultsReducer.State(
            providerID: .testProvider,
            query: "query",
            tracks: [],
            nextCursor: nil,
            status: .idle
        )
        let store = TestStore(initialState: state) {
            ProviderSearchResultsReducer()
        } withDependencies: {
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { _, _ in
                            Issue.record(
                                "An exhausted search must not request another page"
                            )
                            return SearchPage(tracks: [], nextCursor: nil)
                        }
                    )
                ]
            )
        }

        await store.send(.nextPageRequested)
        #expect(store.state == state)
    }

    @Test
    func unresolvedRequestRejectsDuplicateWorkAndStaleResponse() async {
        let cursor = SearchCursor(value: "page-2")
        let state = ProviderSearchResultsReducer.State(
            providerID: .testProvider,
            query: "query",
            tracks: [],
            nextCursor: cursor,
            status: .loading(requestID: UUID(0))
        )
        let store = TestStore(initialState: state) {
            ProviderSearchResultsReducer()
        }

        await store.send(.nextPageRequested)
        await store.send(
            .searchPageResponse(
                UUID(1),
                .success(SearchPage(tracks: [], nextCursor: nil))
            )
        )
        #expect(store.state == state)
    }

    @Test
    func failurePreservesTracksAndCursorThenRetryUsesThatCursor() async {
        let track = makeTrack(nativeID: "1")
        let tracks = IdentifiedArray(uniqueElements: [track])
        let cursor = SearchCursor(value: "page-2")
        let page = SearchPage(tracks: [], nextCursor: nil)
        let store = makeStore(
            tracks: tracks,
            nextCursor: cursor,
            status: .loading(requestID: UUID(99)),
            nextPage: page
        )

        await store.send(
            .searchPageResponse(UUID(99), .failure(.network))
        ) {
            $0.status = .failed(.network)
        }
        #expect(store.state.tracks == tracks)
        #expect(store.state.nextCursor == cursor)

        await store.send(.retryButtonTapped)
        await store.receive(
            .continueSearch(cursor, requestID: UUID(0))
        ) {
            $0.status = .loading(requestID: UUID(0))
        }
        await store.receive(
            .searchPageResponse(UUID(0), .success(page))
        ) {
            $0.nextCursor = nil
            $0.status = .idle
        }
    }

    @Test
    func cancelStopsAnUnresolvedPageRequest() async {
        let cursor = SearchCursor(value: "page-2")
        let store = TestStore(
            initialState: ProviderSearchResultsReducer.State(
                providerID: .testProvider,
                query: "frozen query",
                tracks: [],
                nextCursor: cursor,
                status: .idle
            )
        ) {
            ProviderSearchResultsReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, limit in
                            #expect(request == .continuation(cursor))
                            #expect(limit == 20)
                            return try await Task.never()
                        }
                    )
                ]
            )
        }

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(cursor, requestID: UUID(0))
        ) {
            $0.status = .loading(requestID: UUID(0))
        }
        await store.send(.cancel) {
            $0.status = .idle
        }
    }
}

private extension ProviderSearchResultsReducerTests {
    func makeStore(
        tracks: IdentifiedArrayOf<Track> = [],
        nextCursor: SearchCursor? = nil,
        status: ProviderSearchResultsReducer.Status = .idle,
        nextPage: SearchPage = SearchPage(tracks: [], nextCursor: nil)
    ) -> TestStoreOf<ProviderSearchResultsReducer> {
        TestStore(
            initialState: ProviderSearchResultsReducer.State(
                providerID: .testProvider,
                query: "frozen query",
                tracks: tracks,
                nextCursor: nextCursor,
                status: status
            )
        ) {
            ProviderSearchResultsReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, limit in
                            guard let nextCursor else {
                                Issue.record(
                                    "Continuation requires an owned cursor"
                                )
                                return SearchPage(tracks: [], nextCursor: nil)
                            }
                            #expect(request == .continuation(nextCursor))
                            #expect(limit == 20)
                            return nextPage
                        }
                    )
                ]
            )
        }
    }

    func makeTrack(nativeID: String) -> Track {
        Track(
            id: TrackID(providerID: .testProvider, nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
    }
}
