import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

/// Verifies shared-query coordination across provider rails and the presented
/// provider-results destination.
///
/// Provider request execution remains in the child reducers. App routing,
/// playback, and view mapping remain outside this parent reducer boundary.
@MainActor
struct SearchReducerTests {
    @Test
    func statePlacesLibraryFirstWithoutReorderingOtherUniqueProviders() {
        let first = ProviderID(rawValue: "first")
        let second = ProviderID(rawValue: "second")
        let third = ProviderID(rawValue: "third")

        let state = SearchReducer.State(
            query: "seed",
            providerIDs: [first, .library, second, first, .library, third]
        )

        #expect(state.query == "seed")
        #expect(state.submittedQuery == nil)
        #expect(state.providers.ids.elements == [.library, first, second, third])
        #expect(state.providers.allSatisfy { $0.status == .inactive })
        #expect(state.destination == nil)
    }

    @Test
    func submittedSearchIsInProgressBeforeChildRequestsStart() {
        var state = SearchReducer.State(
            providerIDs: [.library, .jamendo]
        )
        state.submittedQuery = "query"

        #expect(state.isSearchInProgress)
        #expect(!state.hasSearchResults)
        #expect(!state.hasCompletedSearchWithoutResults)
    }

    @Test
    func providerResultsAndAggregateProgressCanCoexist() {
        var state = SearchReducer.State(
            providerIDs: [.library, .jamendo]
        )
        state.submittedQuery = "query"
        state.providers[id: .library]?.status = .loaded(
            ProviderSearchReducer.Page(
                tracks: [makeTrack(providerID: .library)],
                nextCursor: nil
            )
        )
        state.providers[id: .jamendo]?.status = .searching(
            requestID: UUID(0)
        )

        #expect(state.isSearchInProgress)
        #expect(state.hasSearchResults)
        #expect(!state.hasCompletedSearchWithoutResults)
    }

    @Test
    func completedSearchWithoutProviderResultsShowsNoResults() {
        var state = SearchReducer.State(
            providerIDs: [.library, .jamendo]
        )
        state.submittedQuery = "query"
        state.providers[id: .library]?.status = .loaded(emptyPage())
        state.providers[id: .jamendo]?.status = .failed(.network)

        #expect(!state.isSearchInProgress)
        #expect(!state.hasSearchResults)
        #expect(state.hasCompletedSearchWithoutResults)
    }

    @Test
    func completedSearchWithProviderResultsDoesNotShowNoResults() {
        var state = SearchReducer.State(
            providerIDs: [.library, .jamendo]
        )
        state.submittedQuery = "query"
        state.providers[id: .library]?.status = .failed(.network)
        state.providers[id: .jamendo]?.status = .loaded(
            ProviderSearchReducer.Page(
                tracks: [makeTrack(providerID: .jamendo)],
                nextCursor: nil
            )
        )

        #expect(!state.isSearchInProgress)
        #expect(state.hasSearchResults)
        #expect(!state.hasCompletedSearchWithoutResults)
    }

    @Test
    func emptySubmitCancelsEveryProviderWithoutSearching() async {
        let first = ProviderID(rawValue: "first")
        let second = ProviderID(rawValue: "second")
        let searchCount = LockIsolated(0)
        var state = SearchReducer.State(
            query: "   ",
            providerIDs: [first, second]
        )
        state.submittedQuery = "old query"
        state.providers[id: first]?.status = .searching(
            requestID: UUID(99)
        )
        state.providers[id: second]?.status = .loaded(emptyPage())
        let store = makeStore(
            state: state,
            clients: Dictionary(
                uniqueKeysWithValues: [first, second].map { providerID in
                    (
                        providerID,
                        ProviderSearchClient(
                            searchPage: { _, _ in
                                searchCount.withValue { $0 += 1 }
                                return SearchPage(
                                    tracks: [],
                                    nextCursor: nil
                                )
                            }
                        )
                    )
                }
            )
        )

        await store.send(.submitButtonTapped)
        await store.receive(.cancelProviderSearches) {
            $0.submittedQuery = nil
        }
        await receiveProviderCancellations(
            in: store,
            providerIDs: [first, second]
        )

        #expect(searchCount.value == 0)
    }

    @Test
    func validSubmitTrimsAndActivatesEveryProvider() async {
        let providerIDs = [
            ProviderID(rawValue: "first"),
            ProviderID(rawValue: "second"),
            ProviderID(rawValue: "third"),
        ]
        let state = SearchReducer.State(
            query: "  dream pop  ",
            providerIDs: providerIDs
        )
        let store = makeStore(
            state: state,
            clients: suspendedClients(for: providerIDs)
        )

        await store.send(.submitButtonTapped)
        await store.receive(.searchSubmitted("dream pop")) {
            $0.submittedQuery = "dream pop"
        }
        await receiveSearchRequests(
            in: store,
            providerIDs: providerIDs,
            query: "dream pop"
        )

        #expect(store.state.query == "  dream pop  ")
        #expect(store.state.submittedQuery == "dream pop")

        await cancelProviderSearches(
            in: store,
            providerIDs: providerIDs
        )
    }

    @Test
    func submitActivatesEveryOrderedProvider() async {
        let first = ProviderID(rawValue: "first")
        let second = ProviderID(rawValue: "second")
        let third = ProviderID(rawValue: "third")
        let fourth = ProviderID(rawValue: "fourth")
        let fifth = ProviderID(rawValue: "fifth")
        let sixth = ProviderID(rawValue: "sixth")
        let inputProviderIDs = [
            first,
            second,
            .library,
            third,
            fourth,
            fifth,
            sixth,
        ]
        let orderedProviderIDs: [ProviderID] = [
            .library,
            first,
            second,
            third,
            fourth,
            fifth,
            sixth,
        ]
        let state = SearchReducer.State(
            query: "query",
            providerIDs: inputProviderIDs
        )
        let store = makeStore(
            state: state,
            clients: suspendedClients(for: orderedProviderIDs)
        )

        await store.send(.submitButtonTapped)
        await store.receive(.searchSubmitted("query")) {
            $0.submittedQuery = "query"
        }
        await receiveSearchRequests(
            in: store,
            providerIDs: orderedProviderIDs,
            query: "query"
        )

        #expect(
            store.state.providers.ids.elements == orderedProviderIDs
        )

        await cancelProviderSearches(
            in: store,
            providerIDs: orderedProviderIDs
        )
    }

    @Test
    func queryEditingClearsSearchAndRejectsStaleChildResponses() async {
        let searching = ProviderID(rawValue: "searching")
        let loaded = ProviderID(rawValue: "loaded")
        let failed = ProviderID(rawValue: "failed")
        var state = SearchReducer.State(
            query: "old",
            providerIDs: [searching, loaded, failed]
        )
        state.submittedQuery = "old"
        state.providers[id: searching]?.status = .searching(
            requestID: UUID(7)
        )
        state.providers[id: loaded]?.status = .loaded(emptyPage())
        state.providers[id: failed]?.status = .failed(.network)
        state.destination = ProviderSearchResultsReducer.State(
            providerID: loaded,
            query: "old",
            tracks: [],
            nextCursor: nil,
            status: .idle
        )
        let store = makeStore(state: state)

        await store.send(.queryChanged("new")) {
            $0.query = "new"
        }
        await store.receive(.cancelProviderSearches) {
            $0.submittedQuery = nil
            $0.destination = nil
        }
        await receiveProviderCancellations(
            in: store,
            providerIDs: [searching, loaded, failed]
        )

        await store.send(
            .providers(
                .element(
                    id: searching,
                    action: .searchResponse(
                        UUID(7),
                        .success(
                            SearchPage(
                                tracks: [makeTrack(providerID: searching)],
                                nextCursor: nil
                            )
                        )
                    )
                )
            )
        )

        #expect(store.state.submittedQuery == nil)
        #expect(store.state.providers.allSatisfy { $0.status == .inactive })
    }

    @Test
    func seeAllCreatesDestinationFromExactFirstPageSnapshot() async {
        let providerID = ProviderID(rawValue: "provider")
        let tracks = IdentifiedArray(
            uniqueElements: [
                makeTrack(providerID: providerID, nativeID: "first"),
                makeTrack(providerID: providerID, nativeID: "second"),
            ]
        )
        let cursor = SearchCursor(value: "page-2")
        let page = ProviderSearchReducer.Page(
            tracks: tracks,
            nextCursor: cursor
        )
        var state = SearchReducer.State(providerIDs: [providerID])
        state.submittedQuery = "frozen query"
        state.providers[id: providerID]?.status = .loaded(page)
        let store = makeStore(state: state)

        await store.send(
            .providers(
                .element(
                    id: providerID,
                    action: .seeAllButtonTapped
                )
            )
        )
        await store.receive(
            .providers(
                .element(
                    id: providerID,
                    action: .delegate(.seeAllRequested(page))
                )
            )
        ) {
            $0.destination = ProviderSearchResultsReducer.State(
                providerID: providerID,
                query: "frozen query",
                tracks: tracks,
                nextCursor: cursor,
                status: .idle
            )
        }
    }

    @Test
    func destinationPaginationDoesNotMutateRailFirstPage() async {
        let providerID = ProviderID(rawValue: "provider")
        let firstTrack = makeTrack(
            providerID: providerID,
            nativeID: "first"
        )
        let secondTrack = makeTrack(
            providerID: providerID,
            nativeID: "second"
        )
        let firstTracks = IdentifiedArray(uniqueElements: [firstTrack])
        let cursor = SearchCursor(value: "page-2")
        let firstPage = ProviderSearchReducer.Page(
            tracks: firstTracks,
            nextCursor: cursor
        )
        let nextPage = SearchPage(
            tracks: [secondTrack],
            nextCursor: nil
        )
        var state = SearchReducer.State(providerIDs: [providerID])
        state.submittedQuery = "frozen query"
        state.providers[id: providerID]?.status = .loaded(firstPage)
        state.destination = ProviderSearchResultsReducer.State(
            providerID: providerID,
            query: "frozen query",
            tracks: firstTracks,
            nextCursor: cursor,
            status: .idle
        )
        let store = makeStore(
            state: state,
            clients: [
                providerID: ProviderSearchClient(
                    searchPage: { request, limit in
                        #expect(request == .continuation(cursor))
                        #expect(limit == 20)
                        return nextPage
                    }
                )
            ]
        )

        await store.send(
            .destination(.presented(.nextPageRequested))
        )
        await store.receive(
            .destination(
                .presented(
                    .continueSearch(cursor, requestID: UUID(0))
                )
            )
        ) {
            $0.destination?.status = .loading(requestID: UUID(0))
        }
        await store.receive(
            .destination(
                .presented(
                    .searchPageResponse(UUID(0), .success(nextPage))
                )
            )
        ) {
            $0.destination?.tracks.append(secondTrack)
            $0.destination?.nextCursor = nil
            $0.destination?.status = .idle
        }

        #expect(
            store.state.providers[id: providerID]?.status
                == .loaded(firstPage)
        )
        #expect(store.state.destination?.tracks == [firstTrack, secondTrack])
    }

    @Test
    func dismissingDestinationCancelsUnresolvedContinuation() async {
        let providerID = ProviderID(rawValue: "provider")
        let cursor = SearchCursor(value: "page-2")
        let probe = SuspendedOperationProbe<SearchPage>()
        var state = SearchReducer.State(providerIDs: [providerID])
        state.destination = ProviderSearchResultsReducer.State(
            providerID: providerID,
            query: "frozen query",
            tracks: [],
            nextCursor: cursor,
            status: .idle
        )
        let store = makeStore(
            state: state,
            clients: [
                providerID: ProviderSearchClient(
                    searchPage: { _, _ in try await probe.run() }
                )
            ]
        )

        await store.send(
            .destination(.presented(.nextPageRequested))
        )
        await store.receive(
            .destination(
                .presented(
                    .continueSearch(cursor, requestID: UUID(0))
                )
            )
        ) {
            $0.destination?.status = .loading(requestID: UUID(0))
        }
        await probe.waitUntilStarted()

        await store.send(.destination(.dismiss)) {
            $0.destination = nil
        }
        await probe.waitUntilCancelled()

        #expect(probe.hasObservedCancellation)
    }

    @Test
    func selectionsDelegateTheOwningResultSnapshot() async {
        let providerID = ProviderID(rawValue: "provider")
        let firstTrack = makeTrack(
            providerID: providerID,
            nativeID: "first"
        )
        let secondTrack = makeTrack(
            providerID: providerID,
            nativeID: "second"
        )
        let firstTracks = IdentifiedArray(uniqueElements: [firstTrack])
        let allTracks = IdentifiedArray(
            uniqueElements: [firstTrack, secondTrack]
        )
        var state = SearchReducer.State(providerIDs: [providerID])
        state.providers[id: providerID]?.status = .loaded(
            ProviderSearchReducer.Page(
                tracks: firstTracks,
                nextCursor: SearchCursor(value: "page-2")
            )
        )
        state.destination = ProviderSearchResultsReducer.State(
            providerID: providerID,
            query: "frozen query",
            tracks: allTracks,
            nextCursor: nil,
            status: .idle
        )
        let store = makeStore(state: state)

        await store.send(
            .providers(
                .element(
                    id: providerID,
                    action: .resultTapped(firstTrack.id)
                )
            )
        )
        await store.receive(
            .providers(
                .element(
                    id: providerID,
                    action: .delegate(
                        .trackTapped(
                            firstTrack,
                            loadedTracks: firstTracks
                        )
                    )
                )
            )
        )
        await store.receive(
            .delegate(
                .trackTapped(
                    firstTrack,
                    loadedTracks: firstTracks
                )
            )
        )

        await store.send(
            .destination(.presented(.resultTapped(secondTrack.id)))
        )
        await store.receive(
            .destination(
                .presented(
                    .delegate(
                        .trackTapped(
                            secondTrack,
                            loadedTracks: allTracks
                        )
                    )
                )
            )
        )
        await store.receive(
            .delegate(
                .trackTapped(
                    secondTrack,
                    loadedTracks: allTracks
                )
            )
        )
    }

}

private extension SearchReducerTests {
    func makeStore(
        state: SearchReducer.State,
        clients: [ProviderID: ProviderSearchClient] = [:]
    ) -> TestStoreOf<SearchReducer> {
        TestStore(initialState: state) {
            SearchReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: clients
            )
        }
    }

    func suspendedClients(
        for providerIDs: [ProviderID]
    ) -> [ProviderID: ProviderSearchClient] {
        Dictionary(
            uniqueKeysWithValues: providerIDs.map { providerID in
                (
                    providerID,
                    ProviderSearchClient(
                        searchPage: { _, _ in try await Task.never() }
                    )
                )
            }
        )
    }

    func receiveSearchRequests(
        in store: TestStoreOf<SearchReducer>,
        providerIDs: [ProviderID],
        query: String
    ) async {
        for (offset, providerID) in providerIDs.enumerated() {
            await store.receive(
                .providers(
                    .element(
                        id: providerID,
                        action: .searchRequested(query: query)
                    )
                )
            ) {
                $0.providers[id: providerID]?.status = .searching(
                    requestID: UUID(offset)
                )
            }
        }
    }

    func cancelProviderSearches(
        in store: TestStoreOf<SearchReducer>,
        providerIDs: [ProviderID]
    ) async {
        await store.send(.cancelProviderSearches) {
            $0.submittedQuery = nil
            $0.destination = nil
        }
        await receiveProviderCancellations(
            in: store,
            providerIDs: providerIDs
        )
    }

    func receiveProviderCancellations(
        in store: TestStoreOf<SearchReducer>,
        providerIDs: [ProviderID]
    ) async {
        for providerID in providerIDs {
            let action = SearchReducer.Action.providers(
                .element(
                    id: providerID,
                    action: .cancel
                )
            )
            if store.state.providers[id: providerID]?.status == .inactive {
                await store.receive(action)
            } else {
                await store.receive(action) {
                    $0.providers[id: providerID]?.status = .inactive
                }
            }
        }
    }

    func emptyPage() -> ProviderSearchReducer.Page {
        ProviderSearchReducer.Page(
            tracks: [],
            nextCursor: nil
        )
    }

    func makeTrack(
        providerID: ProviderID,
        nativeID: String = "track"
    ) -> Track {
        Track(
            id: TrackID(providerID: providerID, nativeID: nativeID),
            title: "Track",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
    }
}
