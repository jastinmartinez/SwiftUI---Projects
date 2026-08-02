import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

/// Verifies one reusable provider rail's lifecycle and validated delegate facts.
///
/// The tests keep shared-query coordination, destination pagination, navigation,
/// presentation mapping, and App routing outside this reducer boundary.
@MainActor
struct ProviderSearchReducerTests {
    @Test
    func searchUsesTheClientRegisteredForItsProvider() async {
        let track = makeTrack(providerID: .jamendo, nativeID: "1")
        let cursor = SearchCursor(value: "page-2")
        let searchPage = SearchPage(
            tracks: [track],
            nextCursor: cursor
        )
        let otherProviderSearchCount = LockIsolated(0)
        let jamendoSearchCount = LockIsolated(0)
        let store = makeStore(
            providerID: .jamendo,
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
                        #expect(request == .initial(query: "dream pop"))
                        #expect(limit == 20)
                        return searchPage
                    }
                ),
            ]
        )

        await store.send(.searchRequested(query: "dream pop")) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.receive(
            .searchResponse(UUID(0), .success(searchPage))
        ) {
            $0.status = .loaded(
                ProviderSearchReducer.Page(
                    tracks: [track],
                    nextCursor: cursor
                )
            )
        }

        #expect(otherProviderSearchCount.value == 0)
        #expect(jamendoSearchCount.value == 1)
    }

    @Test
    func missingRegistrationFailsClosed() async {
        let otherProviderSearchCount = LockIsolated(0)
        let store = makeStore(
            providerID: .jamendo,
            clients: [
                .testProvider: ProviderSearchClient(
                    searchPage: { _, _ in
                        otherProviderSearchCount.withValue { $0 += 1 }
                        return SearchPage(tracks: [], nextCursor: nil)
                    }
                )
            ]
        )

        await store.send(.searchRequested(query: "query")) {
            $0.status = .searching(requestID: UUID(0))
        }
        await store.receive(
            .searchResponse(
                UUID(0),
                .failure(.providerUnavailable(.jamendo))
            )
        ) {
            $0.status = .failed(.providerUnavailable(.jamendo))
        }

        #expect(otherProviderSearchCount.value == 0)
    }

    @Test
    func staleResponseLeavesStateUnchanged() async {
        let state = ProviderSearchReducer.State(
            providerID: .testProvider,
            status: .searching(requestID: UUID(0))
        )
        let store = TestStore(initialState: state) {
            ProviderSearchReducer()
        }

        await store.send(
            .searchResponse(
                UUID(1),
                .success(SearchPage(tracks: [], nextCursor: nil))
            )
        )

        #expect(store.state == state)
    }

    @Test
    func cancellingOneProviderLeavesSiblingRequestRunning() async {
        let libraryProbe = SuspendedOperationProbe<SearchPage>()
        let jamendoProbe = SuspendedOperationProbe<SearchPage>()
        let clients: [ProviderID: ProviderSearchClient] = [
            .library: ProviderSearchClient(
                searchPage: { _, _ in try await libraryProbe.run() }
            ),
            .jamendo: ProviderSearchClient(
                searchPage: { _, _ in try await jamendoProbe.run() }
            ),
        ]
        let libraryStore = makeStore(
            providerID: .library,
            clients: clients
        )
        let jamendoStore = makeStore(
            providerID: .jamendo,
            clients: clients
        )

        await libraryStore.send(.searchRequested(query: "library")) {
            $0.status = .searching(requestID: UUID(0))
        }
        await jamendoStore.send(.searchRequested(query: "jamendo")) {
            $0.status = .searching(requestID: UUID(0))
        }
        await libraryProbe.waitUntilStarted()
        await jamendoProbe.waitUntilStarted()

        await libraryStore.send(.cancel) {
            $0.status = .inactive
        }
        await libraryProbe.waitUntilCancelled()

        #expect(libraryProbe.hasObservedCancellation)
        #expect(!jamendoProbe.hasObservedCancellation)

        let jamendoPage = SearchPage(tracks: [], nextCursor: nil)
        jamendoProbe.succeed(with: jamendoPage)
        await jamendoStore.receive(
            .searchResponse(UUID(0), .success(jamendoPage))
        ) {
            $0.status = .loaded(
                ProviderSearchReducer.Page(
                    tracks: [],
                    nextCursor: nil
                )
            )
        }
    }

    @Test
    func providerFailureLeavesSiblingStateUntouched() async {
        let libraryProbe = SuspendedOperationProbe<SearchPage>()
        let jamendoProbe = SuspendedOperationProbe<SearchPage>()
        let libraryTrack = makeTrack(
            providerID: .library,
            nativeID: "library"
        )
        let librarySearchPage = SearchPage(
            tracks: [libraryTrack],
            nextCursor: nil
        )
        let clients: [ProviderID: ProviderSearchClient] = [
            .library: ProviderSearchClient(
                searchPage: { _, _ in try await libraryProbe.run() }
            ),
            .jamendo: ProviderSearchClient(
                searchPage: { _, _ in try await jamendoProbe.run() }
            ),
        ]
        let libraryStore = makeStore(
            providerID: .library,
            clients: clients
        )
        let jamendoStore = makeStore(
            providerID: .jamendo,
            clients: clients
        )

        await libraryStore.send(.searchRequested(query: "library")) {
            $0.status = .searching(requestID: UUID(0))
        }
        await jamendoStore.send(.searchRequested(query: "jamendo")) {
            $0.status = .searching(requestID: UUID(0))
        }
        await libraryProbe.waitUntilStarted()
        await jamendoProbe.waitUntilStarted()

        jamendoProbe.fail(with: MusicProviderError.network)
        await jamendoStore.receive(
            .searchResponse(UUID(0), .failure(.network))
        ) {
            $0.status = .failed(.network)
        }
        #expect(
            libraryStore.state.status
                == .searching(requestID: UUID(0))
        )

        libraryProbe.succeed(with: librarySearchPage)
        await libraryStore.receive(
            .searchResponse(UUID(0), .success(librarySearchPage))
        ) {
            $0.status = .loaded(
                ProviderSearchReducer.Page(
                    tracks: [libraryTrack],
                    nextCursor: nil
                )
            )
        }
    }

    @Test
    func seeAllDelegatesExactNonemptyFirstPage() async {
        let track = makeTrack(providerID: .testProvider, nativeID: "1")
        let page = ProviderSearchReducer.Page(
            tracks: [track],
            nextCursor: SearchCursor(value: "page-2")
        )
        let loadedStore = makeStore(
            providerID: .testProvider,
            status: .loaded(page)
        )

        await loadedStore.send(.seeAllButtonTapped)
        await loadedStore.receive(.delegate(.seeAllRequested(page)))

        let emptyStore = makeStore(
            providerID: .testProvider,
            status: .loaded(emptyPage())
        )
        await emptyStore.send(.seeAllButtonTapped)

        for status in statusesWithoutLoadedPage() {
            let store = makeStore(
                providerID: .testProvider,
                status: status
            )
            await store.send(.seeAllButtonTapped)
        }
    }

    @Test
    func trackSelectionDelegatesTrackWithCompleteFirstPage() async {
        let first = makeTrack(providerID: .testProvider, nativeID: "1")
        let second = makeTrack(providerID: .testProvider, nativeID: "2")
        let tracks = IdentifiedArray(uniqueElements: [first, second])
        let store = makeStore(
            providerID: .testProvider,
            status: .loaded(
                ProviderSearchReducer.Page(
                    tracks: tracks,
                    nextCursor: nil
                )
            )
        )

        await store.send(.resultTapped(second.id))
        await store.receive(
            .delegate(
                .trackTapped(
                    second,
                    loadedTracks: tracks
                )
            )
        )

        await store.send(
            .resultTapped(
                TrackID(providerID: .testProvider, nativeID: "missing")
            )
        )
    }

}

private extension ProviderSearchReducerTests {
    func makeStore(
        providerID: ProviderID,
        status: ProviderSearchReducer.Status = .inactive,
        clients: [ProviderID: ProviderSearchClient] = [:]
    ) -> TestStoreOf<ProviderSearchReducer> {
        TestStore(
            initialState: ProviderSearchReducer.State(
                providerID: providerID,
                status: status
            )
        ) {
            ProviderSearchReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: clients
            )
        }
    }

    func emptyPage() -> ProviderSearchReducer.Page {
        ProviderSearchReducer.Page(
            tracks: [],
            nextCursor: nil
        )
    }

    func statusesWithoutLoadedPage() -> [ProviderSearchReducer.Status] {
        [
            .inactive,
            .searching(requestID: UUID(0)),
            .failed(.network),
        ]
    }

    func makeTrack(
        providerID: ProviderID,
        nativeID: String
    ) -> Track {
        Track(
            id: TrackID(providerID: providerID, nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
    }
}
