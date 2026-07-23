import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPaginationFeatureTests {
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
        let store = makeStore(
            tracks: [first],
            nextCursor: cursor,
            status: .idle,
            nextPage: page
        )

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(
                providerID: .appleMusic,
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
    }

    @Test
    func exhaustedSearchDoesNotRequestAnotherPage() async {
        let state = SearchPaginationFeature.State(
            tracks: [],
            nextCursor: nil,
            status: .idle,
            providerID: .appleMusic
        )
        let store = TestStore(initialState: state) {
            SearchPaginationFeature()
        } withDependencies: {
            $0.providerSearch.searchPage = { _, _, _ in
                Issue.record("An exhausted search must not request another page")
                return SearchPage(tracks: [], nextCursor: nil)
            }
        }

        await store.send(.nextPageRequested)
        #expect(store.state == state)
    }

    @Test
    func unresolvedRequestRejectsDuplicateAndStaleResponses() async {
        let cursor = SearchCursor(value: "page-2")
        let state = SearchPaginationFeature.State(
            tracks: [],
            nextCursor: cursor,
            status: .loading(requestID: UUID(0)),
            providerID: .appleMusic
        )
        let store = TestStore(initialState: state) {
            SearchPaginationFeature()
        } withDependencies: {
            $0.providerSearch.searchPage = { _, _, _ in
                Issue.record("An unresolved request must reject duplicate work")
                return SearchPage(tracks: [], nextCursor: nil)
            }
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
                providerID: .appleMusic,
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
            initialState: SearchPaginationFeature.State(
                tracks: [],
                nextCursor: SearchCursor(value: "page-2"),
                status: .idle,
                providerID: .appleMusic
            )
        ) {
            SearchPaginationFeature()
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

        await store.send(.nextPageRequested)
        await store.receive(
            .continueSearch(
                providerID: .appleMusic,
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
        status: SearchPaginationFeature.Status,
        nextPage: SearchPage
    ) -> TestStoreOf<SearchPaginationFeature> {
        TestStore(
            initialState: SearchPaginationFeature.State(
                tracks: .init(uniqueElements: tracks),
                nextCursor: nextCursor,
                status: status,
                providerID: .appleMusic
            )
        ) {
            SearchPaginationFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearch.searchPage = { providerID, request, limit in
                #expect(providerID == .appleMusic)
                guard let nextCursor else {
                    Issue.record("Pagination requires a continuation cursor")
                    return SearchPage(tracks: [], nextCursor: nil)
                }
                #expect(request == .continuation(nextCursor))
                #expect(limit == 20)
                return nextPage
            }
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
