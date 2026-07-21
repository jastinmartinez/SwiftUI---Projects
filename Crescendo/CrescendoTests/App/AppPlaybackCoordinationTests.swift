import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func firstEligibleSelectionRoutesLoadedResultsAndOpensPlayer() async {
        let songs = makeSongs()
        let loadedResults = IdentifiedArray(uniqueElements: songs)
        let store = makeStore {
            $0.playbackControl.playQueue = { _, _ in
                try await Task.sleep(for: .seconds(60))
            }
        }

        await store.send(
            .search(
                .delegate(
                    .songTapped(
                        songs[1],
                        loadedResults: loadedResults
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    songs[1],
                    loadedResults: loadedResults,
                    providerID: providerID,
                    playbackEligibility: .eligible
                )
            )
        ) {
            $0.playback.isPlayerPresented = true
            $0.playback.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: loadedResults,
                    startingItemID: songs[1].id
                )
            )
            $0.playback.playbackEligibility = .eligible
            $0.playback.failure = nil
        }
        await store.receive(
            .playback(
                .performQueueReplacement(
                    requestID: UUID(0),
                    itemIDs: Array(loadedResults.ids),
                    startingItemID: songs[1].id
                )
            )
        )
        await store.send(.playback(.cancelPendingOperation)) {
            $0.playback.pendingOperation = nil
        }
    }

    @Test
    func initialIneligibleSelectionOpensPlayerWithoutCallingPlayback() async {
        let song = makeSong(nativeID: "restricted")
        let loadedResults = IdentifiedArray(uniqueElements: [song])
        let calls = LockIsolated(0)
        let store = makeStore(
            access: MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .ineligible
            )
        ) {
            $0.playbackControl.playQueue = { _, _ in
                calls.withValue { $0 += 1 }
            }
        }

        await store.send(
            .search(
                .delegate(
                    .songTapped(
                        song,
                        loadedResults: loadedResults
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    song,
                    loadedResults: loadedResults,
                    providerID: providerID,
                    playbackEligibility: .ineligible
                )
            )
        ) {
            $0.playback.isPlayerPresented = true
            $0.playback.playbackEligibility = .ineligible
            $0.playback.failure = nil
        }

        #expect(calls.value == 0)
        #expect(store.state.playback.queue.currentItem == nil)
    }

    @Test
    func laterSelectionReplacesPlaybackWithoutReopeningDismissedPlayer() async {
        let currentSongs = makeSongs(prefix: "current")
        let currentQueue = IdentifiedArray(uniqueElements: currentSongs)
        let nextSongs = makeSongs(prefix: "next")
        let nextQueue = IdentifiedArray(uniqueElements: nextSongs)
        let store = makeStore(
            playbackQueue: .init(
                songs: currentQueue,
                currentItemID: currentSongs[0].id
            ),
            isPlayerPresented: false
        ) {
            $0.playbackControl.playQueue = { _, _ in
                try await Task.sleep(for: .seconds(60))
            }
        }

        await store.send(
            .search(
                .delegate(
                    .songTapped(
                        nextSongs[0],
                        loadedResults: nextQueue
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    nextSongs[0],
                    loadedResults: nextQueue,
                    providerID: providerID,
                    playbackEligibility: .eligible
                )
            )
        ) {
            $0.playback.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: nextQueue,
                    startingItemID: nextSongs[0].id
                )
            )
            $0.playback.playbackEligibility = .eligible
            $0.playback.failure = nil
        }
        await store.receive(
            .playback(
                .performQueueReplacement(
                    requestID: UUID(0),
                    itemIDs: Array(nextQueue.ids),
                    startingItemID: nextSongs[0].id
                )
            )
        )

        #expect(!store.state.playback.isPlayerPresented)
        #expect(store.state.playback.queue.songs == currentQueue)

        await store.send(.playback(.cancelPendingOperation)) {
            $0.playback.pendingOperation = nil
        }
    }

    @Test
    func laterPaginatedResultsAreFrozenOnlyWhenLaterSongIsTapped() async {
        let firstPageSongs = makeSongs(prefix: "first")
        let firstPage = IdentifiedArray(uniqueElements: firstPageSongs)
        let laterSong = makeSong(nativeID: "later")
        let laterSongs = firstPageSongs + [laterSong]
        let laterResults = IdentifiedArray(uniqueElements: laterSongs)
        let cursor = SearchCursor(value: "page-2")
        var state = makeState(
            playbackQueue: PlaybackQueueFeature.State(
                songs: firstPage,
                currentItemID: firstPageSongs[0].id
            )
        )
        state.search.status = .loaded(
            SearchPaginationFeature.State(
                songs: firstPage,
                nextCursor: cursor,
                status: .idle
            )
        )
        let store = makeStore(state: state) {
            $0.providerSearch.searchPage = { request, limit in
                #expect(request == .continuation(cursor))
                #expect(limit == 20)
                return SearchPage(songs: [laterSong], nextCursor: nil)
            }
            $0.playbackControl.playQueue = { _, _ in
                try await Task.sleep(for: .seconds(60))
            }
        }

        await store.send(.search(.pagination(.nextPageRequested)))
        await store.receive(
            .search(
                .pagination(
                    .continueSearch(cursor: cursor, requestID: UUID(0))
                )
            )
        ) {
            guard case .loaded(var pagination) = $0.search.status else {
                return
            }
            pagination.status = .loading(requestID: UUID(0))
            $0.search.status = .loaded(pagination)
        }
        await store.receive(
            .search(
                .pagination(
                    .searchPageResponse(
                        UUID(0),
                        .success(
                            SearchPage(songs: [laterSong], nextCursor: nil)
                        )
                    )
                )
            )
        ) {
            guard case .loaded(var pagination) = $0.search.status else {
                return
            }
            pagination.songs.append(laterSong)
            pagination.nextCursor = nil
            pagination.status = .idle
            $0.search.status = .loaded(pagination)
        }

        #expect(store.state.playback.queue.songs == firstPage)

        await store.send(.search(.resultTapped(laterSong.id)))
        await store.receive(
            .search(.delegate(.songTapped(laterSong, loadedResults: laterResults)))
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    laterSong,
                    loadedResults: laterResults,
                    providerID: providerID,
                    playbackEligibility: .eligible
                )
            )
        ) {
            $0.playback.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(1),
                    songs: laterResults,
                    startingItemID: laterSong.id
                )
            )
            $0.playback.playbackEligibility = .eligible
            $0.playback.failure = nil
        }
        await store.receive(
            .playback(
                .performQueueReplacement(
                    requestID: UUID(1),
                    itemIDs: Array(laterResults.ids),
                    startingItemID: laterSong.id
                )
            )
        )

        #expect(store.state.playback.queue.songs == firstPage)
        guard
            case .queueReplacement(let replacement) =
                store.state.playback.pendingOperation
        else {
            Issue.record("Expected a pending queue replacement")
            return
        }
        #expect(replacement.songs == laterResults)

        await store.send(.playback(.cancelPendingOperation)) {
            $0.playback.pendingOperation = nil
        }
    }

    @Test
    func providerSwitchRejectsSearchSelection() async {
        let songs = makeSongs()
        let loadedResults = IdentifiedArray(uniqueElements: songs)
        let state = makeState(
            providerSwitch: ProviderSwitchFeature.State(
                sourceProviderID: providerID,
                phase: .ready(targetProviderID: "other")
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .search(
                .delegate(
                    .songTapped(
                        songs[0],
                        loadedResults: loadedResults
                    )
                )
            )
        )

        #expect(store.state == state)
    }

    // MARK: - Helpers

    private let providerID = ProviderID(rawValue: "fake")

    private func makeStore(
        state: AppFeature.State? = nil,
        access: MusicProviderAccess = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        ),
        playbackQueue: PlaybackQueueFeature.State = .init(
            songs: [],
            currentItemID: nil
        ),
        isPlayerPresented: Bool = false,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<AppFeature> {
        TestStore(
            initialState: state
                ?? makeState(
                    access: access,
                    playbackQueue: playbackQueue,
                    isPlayerPresented: isPlayerPresented
                )
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            configureDependencies(&$0)
        }
    }

    private func makeState(
        access: MusicProviderAccess = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        ),
        playbackQueue: PlaybackQueueFeature.State = .init(
            songs: [],
            currentItemID: nil
        ),
        isPlayerPresented: Bool = false,
        providerSwitch: ProviderSwitchFeature.State? = nil
    ) -> AppFeature.State {
        AppFeature.State(
            providerConnection: ProviderConnectionFeature.State(
                providers: [
                    ProviderDescriptor(
                        id: providerID,
                        name: "Fake",
                        musicCapabilities: .allEnabled
                    ),
                    ProviderDescriptor(
                        id: "other",
                        name: "Other",
                        musicCapabilities: .allEnabled
                    ),
                ],
                connection: .connected(
                    providerID: providerID,
                    access: access
                )
            ),
            search: SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: access
            ),
            playback: PlaybackFeature.State(
                providerID: providerID,
                queue: playbackQueue,
                status: playbackQueue.currentItem == nil ? .idle : .playing,
                failure: nil,
                playbackEligibility: access.playbackEligibility,
                capabilities: .allEnabled,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: 0,
                    interaction: .idle
                ),
                pendingOperation: nil,
                pendingReset: nil,
                isPlayerPresented: isPlayerPresented
            ),
            providerSwitch: providerSwitch
        )
    }

    private func makeSongs(prefix: String = "song") -> [SongSummary] {
        [
            makeSong(nativeID: "\(prefix)-1"),
            makeSong(nativeID: "\(prefix)-2"),
            makeSong(nativeID: "\(prefix)-3"),
        ]
    }

    private func makeSong(nativeID: String) -> SongSummary {
        SongSummary(
            id: .init(providerID: providerID, nativeID: nativeID),
            title: nativeID,
            artistName: "Artist",
            artworkURL: nil,
            duration: 180
        )
    }
}
