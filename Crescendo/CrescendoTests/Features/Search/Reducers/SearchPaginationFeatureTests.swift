import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPaginationFeatureTests {
    @Test
    func nextPageAppendsUniqueSongsAndStoresContinuation() async {
        let first = makeSong(nativeID: "1")
        let duplicate = makeSong(nativeID: "1")
        let second = makeSong(nativeID: "2")
        let cursor = SearchCursor(value: "page-2")
        let nextCursor = SearchCursor(value: "page-3")
        let page = SearchPage(
            songs: [duplicate, second],
            nextCursor: nextCursor
        )
        let store = makeStore(
            songs: [first],
            nextCursor: cursor,
            status: .idle,
            nextPage: page
        )

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(cursor: cursor, requestID: UUID(0))
        ) {
            $0.status = .loading(requestID: UUID(0))
        }
        await store.receive(
            .searchPageResponse(UUID(0), .success(page))
        ) {
            $0.songs.append(second)
            $0.nextCursor = nextCursor
            $0.status = .idle
        }
    }

    @Test
    func exhaustedSearchDoesNotRequestAnotherPage() async {
        let state = SearchPaginationFeature.State(
            songs: [],
            nextCursor: nil,
            status: .idle
        )
        let store = TestStore(initialState: state) {
            SearchPaginationFeature()
        } withDependencies: {
            $0.providerSearch.searchPage = { _, _ in
                Issue.record("An exhausted search must not request another page")
                return SearchPage(songs: [], nextCursor: nil)
            }
        }

        await store.send(.nextPageRequested)
        #expect(store.state == state)
    }

    @Test
    func unresolvedRequestRejectsDuplicateAndStaleResponses() async {
        let cursor = SearchCursor(value: "page-2")
        let state = SearchPaginationFeature.State(
            songs: [],
            nextCursor: cursor,
            status: .loading(requestID: UUID(0))
        )
        let store = TestStore(initialState: state) {
            SearchPaginationFeature()
        } withDependencies: {
            $0.providerSearch.searchPage = { _, _ in
                Issue.record("An unresolved request must reject duplicate work")
                return SearchPage(songs: [], nextCursor: nil)
            }
        }

        await store.send(.nextPageRequested)
        await store.send(
            .searchPageResponse(
                UUID(1),
                .success(SearchPage(songs: [], nextCursor: nil))
            )
        )
        #expect(store.state == state)
    }

    @Test
    func failurePreservesSongsAndCursorThenRetryUsesThatCursor() async {
        let song = makeSong(nativeID: "1")
        let cursor = SearchCursor(value: "page-2")
        let page = SearchPage(songs: [], nextCursor: nil)
        let store = makeStore(
            songs: [song],
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
            .continueSearch(cursor: cursor, requestID: UUID(0))
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
            initialState: SearchPaginationFeature.State(
                songs: [],
                nextCursor: SearchCursor(value: "page-2"),
                status: .idle
            )
        ) {
            SearchPaginationFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearch.searchPage = { request, _ in
                let expectedRequest = SearchPageRequest.continuation(
                    SearchCursor(value: "page-2")
                )
                #expect(request == expectedRequest)
                return try await Task.never()
            }
        }

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(
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
        songs: [SongSummary],
        nextCursor: SearchCursor?,
        status: SearchPaginationFeature.Status,
        nextPage: SearchPage
    ) -> TestStoreOf<SearchPaginationFeature> {
        TestStore(
            initialState: SearchPaginationFeature.State(
                songs: .init(uniqueElements: songs),
                nextCursor: nextCursor,
                status: status
            )
        ) {
            SearchPaginationFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearch.searchPage = { request, limit in
                guard let nextCursor else {
                    Issue.record("Pagination requires a continuation cursor")
                    return SearchPage(songs: [], nextCursor: nil)
                }
                #expect(request == .continuation(nextCursor))
                #expect(limit == 20)
                return nextPage
            }
        }
    }

    private func makeSong(nativeID: String) -> SongSummary {
        SongSummary(
            id: MusicItemID(providerID: "fake", nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
