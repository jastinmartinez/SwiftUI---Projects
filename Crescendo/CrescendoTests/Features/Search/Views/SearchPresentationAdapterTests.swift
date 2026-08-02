import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPresentationAdapterTests {
    @Test
    func searchHeaderRequiresOnlyANonemptyTrimmedQuery() {
        let enabled = SearchHeaderView.Model(
            makeStore(query: " vela ")
        )
        let disabled = SearchHeaderView.Model(
            makeStore(query: "   ")
        )

        #expect(enabled.isSearchEnabled)
        #expect(!disabled.isSearchEnabled)
    }

    @Test
    func firstProviderPageMapsToProviderNeutralResultRows() throws {
        let firstTrack = makeTrack()
        let secondTrack = makeTrack(nativeID: "2")
        let model = SearchResultsView.Model(
            makeStore(
                query: "result",
                status: loadedStatus(
                    tracks: [firstTrack, secondTrack],
                    nextCursor: SearchCursor(value: "next")
                )
            )
        )

        let results = try results(from: model)

        #expect(results.summary == "2 songs")
        #expect(results.rows.map(\.id) == [firstTrack.id, secondTrack.id])
        #expect(results.rows.allSatisfy { $0.paginationTriggerID == nil })
        #expect(results.rows.first?.song.durationText == nil)
        #expect(results.footer.content == .hidden)
    }

    @Test
    func trackWithoutAnArtistMapsToLocalizedPresentationFallback() throws {
        let track = Track(
            id: .init(providerID: .library, nativeID: "library"),
            title: "Library Track",
            artistName: nil,
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
        let model = SearchResultsView.Model(
            makeStore(
                query: "library",
                status: loadedStatus(
                    tracks: [track],
                    nextCursor: nil
                )
            )
        )

        #expect(
            try results(from: model).rows.first?.song.artistName
                == Locs.Common.unknownArtist
        )
    }

    @Test
    func providerFailureMapsToRetryPresentation() {
        let model = SearchResultsView.Model(
            makeStore(query: "result", status: .failed(.network))
        )

        guard case .failed = model.content else {
            Issue.record("Expected failure presentation")
            return
        }
    }
}

private extension SearchPresentationAdapterTests {
    func makeStore(
        query: String,
        status: ProviderSearchReducer.Status = .inactive
    ) -> StoreOf<SearchReducer> {
        var state = SearchReducer.State(
            query: query,
            providerIDs: [.testProvider]
        )
        state.providers[id: .testProvider]?.status = status
        return Store(initialState: state) {
            SearchReducer()
        }
    }

    func loadedStatus(
        tracks: [Track],
        nextCursor: SearchCursor?
    ) -> ProviderSearchReducer.Status {
        .loaded(
            ProviderSearchReducer.Page(
                tracks: .init(uniqueElements: tracks),
                nextCursor: nextCursor
            )
        )
    }

    func results(
        from model: SearchResultsView.Model
    ) throws -> SearchResultListView.Model {
        guard case .results(let results) = model.content else {
            throw TestFailure.expectedLoadedResults
        }
        return results
    }

    func makeTrack(nativeID: String = "1") -> Track {
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
