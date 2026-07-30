import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPresentationAdapterTests {
    @Test
    func searchHeaderRequiresOnlyANonemptyTrimmedQuery() {
        let enabled = SearchHeaderView.Model(
            makeStore(query: " vela ", status: .idle)
        )
        let disabled = SearchHeaderView.Model(
            makeStore(query: "   ", status: .idle)
        )

        #expect(enabled.isSearchEnabled)
        #expect(!disabled.isSearchEnabled)
    }

    @Test
    func loadedTracksMapToProviderNeutralResultRows() {
        let track = makeTrack()
        let model = SearchResultsView.Model(
            makeStore(
                query: "result",
                status: loadedStatus(
                    tracks: [track],
                    nextCursor: SearchCursor(value: "next"),
                    paginationStatus: .idle
                )
            )
        )

        guard case .results(let results) = model.content else {
            Issue.record("Expected loaded results")
            return
        }

        #expect(results.summary == "1 song")
        #expect(results.rows.map(\.id) == [track.id])
        #expect(results.rows.map(\.paginationTriggerID) == ["next"])
        #expect(results.rows.first?.song.durationText == nil)
        #expect(results.footer.content == .hidden)
    }

    @Test
    func nextPageTriggerMapsOnlyToLastResultRow() {
        let firstTrack = makeTrack()
        let lastTrack = makeTrack(nativeID: "2")
        let model = SearchResultsView.Model(
            makeStore(
                query: "result",
                status: loadedStatus(
                    tracks: [firstTrack, lastTrack],
                    nextCursor: SearchCursor(value: "next"),
                    paginationStatus: .idle
                )
            )
        )

        guard case .results(let results) = model.content else {
            Issue.record("Expected loaded results")
            return
        }

        #expect(results.rows.map(\.paginationTriggerID) == [nil, "next"])
    }

    @Test
    func loadedPaginationMapsFooterPresentation() throws {
        let cursor = SearchCursor(value: "next")
        let hidden = makeResultsModel(
            nextCursor: nil,
            paginationStatus: .idle
        )
        let ready = makeResultsModel(
            nextCursor: cursor,
            paginationStatus: .idle
        )
        let loading = makeResultsModel(
            nextCursor: cursor,
            paginationStatus: .loading(requestID: UUID(0))
        )
        let failed = makeResultsModel(
            nextCursor: cursor,
            paginationStatus: .failed(.network)
        )

        #expect(try footer(from: hidden).content == .hidden)
        #expect(try footer(from: ready).content == .hidden)
        #expect(try footer(from: loading).content == .loading)
        #expect(try footer(from: failed).content == .failed)
    }

    @Test(arguments: [
        SearchPaginationReducer.Status.idle,
        .failed(.network),
    ])
    func paginationCallbackStartsTheExpectedPageRequest(
        paginationStatus: SearchPaginationReducer.Status
    ) throws {
        let store = Store(
            initialState: SearchReducer.State(
                query: "result",
                status: loadedStatus(
                    tracks: [makeTrack()],
                    nextCursor: SearchCursor(value: "next"),
                    paginationStatus: paginationStatus
                ),
                providerID: .testProvider
            )
        ) {
            SearchReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, _ in
                            let expectedRequest = SearchPageRequest.continuation(
                                SearchCursor(value: "next")
                            )
                            #expect(request == expectedRequest)
                            return try await Task.never()
                        }
                    )
                ]
            )
        }
        let results = try results(from: SearchResultsView.Model(store))

        switch paginationStatus {
        case .idle:
            results.onLoadNextPage()
        case .failed:
            results.footer.onRetry()
        case .loading:
            Issue.record("This test covers only actionable footer states")
        }

        guard case .loaded(let pagination) = store.status else {
            Issue.record("Expected loaded pagination state")
            return
        }
        #expect(pagination.status == .loading(requestID: UUID(0)))
    }

    private func makeStore(
        query: String,
        status: SearchReducer.Status
    ) -> StoreOf<SearchReducer> {
        Store(
            initialState: SearchReducer.State(
                query: query,
                status: status,
                providerID: .testProvider
            )
        ) {
            SearchReducer()
        }
    }

    private func loadedStatus(
        tracks: [Track],
        nextCursor: SearchCursor?,
        paginationStatus: SearchPaginationReducer.Status
    ) -> SearchReducer.Status {
        .loaded(
            SearchPaginationReducer.State(
                tracks: .init(uniqueElements: tracks),
                nextCursor: nextCursor,
                status: paginationStatus,
                providerID: .testProvider
            )
        )
    }

    private func makeResultsModel(
        nextCursor: SearchCursor?,
        paginationStatus: SearchPaginationReducer.Status
    ) -> SearchResultsView.Model {
        SearchResultsView.Model(
            makeStore(
                query: "result",
                status: loadedStatus(
                    tracks: [makeTrack()],
                    nextCursor: nextCursor,
                    paginationStatus: paginationStatus
                )
            )
        )
    }

    private func footer(
        from model: SearchResultsView.Model
    ) throws -> SearchPaginationFooterView.Model {
        try results(from: model).footer
    }

    private func results(
        from model: SearchResultsView.Model
    ) throws -> SearchResultListView.Model {
        guard case .results(let results) = model.content else {
            throw TestFailure.expectedLoadedResults
        }
        return results
    }

    private func makeTrack(nativeID: String = "1") -> Track {
        Track(
            id: .init(providerID: "fake", nativeID: nativeID),
            title: "Result",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            duration: 215
        )
    }
}

private enum TestFailure: Error {
    case expectedLoadedResults
}
