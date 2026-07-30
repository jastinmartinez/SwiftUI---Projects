import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPaginationReducerTests {
    @Test
    func nextPageAppendsUniqueSongsAndStoresContinuation() async {
        let first = makeTrack(nativeID: "1")
        let duplicate = makeTrack(nativeID: "1")
        let second = makeTrack(nativeID: "2")
        let cursor = SearchCursor(value: "page-2")
        let nextCursor = SearchCursor(value: "page-3")
        let page = SearchPage(
            tracks: [duplicate, second],
            nextCursor: nextCursor
        )
        let testProviderSearchCount = LockIsolated(0)
        let jamendoSearchCount = LockIsolated(0)
        let store = TestStore(
            initialState: SearchPaginationReducer.State(
                tracks: [first],
                nextCursor: cursor,
                status: .idle,
                providerID: .jamendo
            )
        ) {
            SearchPaginationReducer()
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
            .continueSearch(
                providerID: .jamendo,
                cursor: cursor,
                requestID: UUID(0)
            )
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

        #expect(testProviderSearchCount.value == 0)
        #expect(jamendoSearchCount.value == 1)
    }

    @Test
    func missingSearchRegistrationFailsClosedWithoutUsingAnotherProvider() async {
        let testProviderSearchCount = LockIsolated(0)
        let cursor = SearchCursor(value: "page-2")
        let store = TestStore(
            initialState: SearchPaginationReducer.State(
                tracks: [],
                nextCursor: cursor,
                status: .idle,
                providerID: .jamendo
            )
        ) {
            SearchPaginationReducer()
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

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(
                providerID: .jamendo,
                cursor: cursor,
                requestID: UUID(0)
            )
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

        #expect(testProviderSearchCount.value == 0)
    }

    @Test
    func exhaustedSearchDoesNotRequestAnotherPage() async {
        let state = SearchPaginationReducer.State(
            tracks: [],
            nextCursor: nil,
            status: .idle,
            providerID: .testProvider
        )
        let store = TestStore(initialState: state) {
            SearchPaginationReducer()
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
    func unresolvedRequestRejectsDuplicateAndStaleResponses() async {
        let cursor = SearchCursor(value: "page-2")
        let state = SearchPaginationReducer.State(
            tracks: [],
            nextCursor: cursor,
            status: .loading(requestID: UUID(0)),
            providerID: .testProvider
        )
        let store = TestStore(initialState: state) {
            SearchPaginationReducer()
        } withDependencies: {
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { _, _ in
                            Issue.record(
                                "An unresolved request must reject duplicate work"
                            )
                            return SearchPage(tracks: [], nextCursor: nil)
                        }
                    )
                ]
            )
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
    func failurePreservesSongsAndCursorThenRetryUsesThatCursor() async {
        let song = makeTrack(nativeID: "1")
        let cursor = SearchCursor(value: "page-2")
        let page = SearchPage(tracks: [], nextCursor: nil)
        let store = makeStore(
            tracks: [song],
            nextCursor: cursor,
            status: .loading(requestID: UUID(99)),
            nextPage: page
        )

        await store.send(
            .searchPageResponse(UUID(99), .failure(.network))
        ) {
            $0.status = .failed(.network)
        }
        await store.send(.retryButtonTapped)
        await store.receive(
            .continueSearch(
                providerID: .testProvider,
                cursor: cursor,
                requestID: UUID(0)
            )
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
        let store = TestStore(
            initialState: SearchPaginationReducer.State(
                tracks: [],
                nextCursor: SearchCursor(value: "page-2"),
                status: .idle,
                providerID: .testProvider
            )
        ) {
            SearchPaginationReducer()
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

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(
                providerID: .testProvider,
                cursor: SearchCursor(value: "page-2"),
                requestID: UUID(0)
            )
        ) {
            $0.status = .loading(requestID: UUID(0))
        }
        await store.send(.cancel) {
            $0.status = .idle
        }
    }

    // MARK: - Helpers

    private func makeStore(
        tracks: [Track],
        nextCursor: SearchCursor?,
        status: SearchPaginationReducer.Status,
        nextPage: SearchPage
    ) -> TestStoreOf<SearchPaginationReducer> {
        TestStore(
            initialState: SearchPaginationReducer.State(
                tracks: .init(uniqueElements: tracks),
                nextCursor: nextCursor,
                status: status,
                providerID: .testProvider
            )
        ) {
            SearchPaginationReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, limit in
                            guard let nextCursor else {
                                Issue.record(
                                    "Pagination requires a continuation cursor"
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

    private func makeTrack(nativeID: String) -> Track {
        Track(
            id: TrackID(providerID: "fake", nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
    }
}
