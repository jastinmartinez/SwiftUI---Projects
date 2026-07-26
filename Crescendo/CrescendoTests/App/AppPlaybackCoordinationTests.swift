import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func firstEligibleSelectionRoutesLoadedResultsAndOpensPlayer() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore {
            $0.playbackQueue.replace = { _, _ in
                try await Task.sleep(for: .seconds(60))
            }
        }

        await store.send(
            .search(
                .delegate(
                    .trackTapped(
                        tracks[1],
                        loadedResults: loadedResults
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    tracks[1],
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
                    tracks: loadedResults,
                    targetTrackID: tracks[1].id
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
                    startingItemID: tracks[1].id
                )
            )
        )
        await store.send(.playback(.cancelPendingOperation)) {
            $0.playback.pendingOperation = nil
        }
    }

    @Test
    func initialIneligibleSelectionOpensPlayerWithoutCallingPlayback() async {
        let song = makeTrack(nativeID: "restricted")
        let loadedResults = IdentifiedArray(uniqueElements: [song])
        let calls = LockIsolated(0)
        let store = makeStore(
            access: MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .ineligible
            )
        ) {
            $0.playbackQueue.replace = { _, _ in
                calls.withValue { $0 += 1 }
            }
        }

        await store.send(
            .search(
                .delegate(
                    .trackTapped(
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
        #expect(store.state.playback.queue.currentTrack == nil)
    }

    @Test
    func laterSelectionReplacesPlaybackWithoutReopeningDismissedPlayer() async {
        let currentSongs = makeTracks(prefix: "current")
        let currentQueue = IdentifiedArray(uniqueElements: currentSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextQueue = IdentifiedArray(uniqueElements: nextSongs)
        let store = makeStore(
            playbackQueue: .init(
                tracks: currentQueue,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(currentQueue.ids)),
                currentTrackID: currentSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            isPlayerPresented: false
        ) {
            $0.playbackQueue.replace = { _, _ in
                try await Task.sleep(for: .seconds(60))
            }
        }

        await store.send(
            .search(
                .delegate(
                    .trackTapped(
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
                    tracks: nextQueue,
                    targetTrackID: nextSongs[0].id
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
        #expect(store.state.playback.queue.tracks == currentQueue)

        await store.send(.playback(.cancelPendingOperation)) {
            $0.playback.pendingOperation = nil
        }
    }

    @Test
    func laterPaginatedResultsAreFrozenOnlyWhenLaterSongIsTapped() async {
        let firstPageSongs = makeTracks(prefix: "first")
        let firstPage = IdentifiedArray(uniqueElements: firstPageSongs)
        let laterSong = makeTrack(nativeID: "later")
        let laterSongs = firstPageSongs + [laterSong]
        let laterResults = IdentifiedArray(uniqueElements: laterSongs)
        let cursor = SearchCursor(value: "page-2")
        var state = makeState(
            playbackQueue: PlaybackQueueFeature.State(
                tracks: firstPage,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(firstPage.ids)),
                currentTrackID: firstPageSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            )
        )
        state.search.status = .loaded(
            SearchPaginationFeature.State(
                tracks: firstPage,
                nextCursor: cursor,
                status: .idle,
                providerID: providerID
            )
        )
        let store = makeStore(state: state) {
            $0.providerSearch.searchPage = { requestProviderID, request, limit in
                #expect(requestProviderID == providerID)
                #expect(request == .continuation(cursor))
                #expect(limit == 20)
                return SearchPage(tracks: [laterSong], nextCursor: nil)
            }
            $0.playbackQueue.replace = { _, _ in
                try await Task.sleep(for: .seconds(60))
            }
        }

        await store.send(.search(.pagination(.nextPageRequested)))
        await store.receive(
            .search(
                .pagination(
                    .continueSearch(
                        providerID: providerID,
                        cursor: cursor,
                        requestID: UUID(0)
                    )
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
                            SearchPage(tracks: [laterSong], nextCursor: nil)
                        )
                    )
                )
            )
        ) {
            guard case .loaded(var pagination) = $0.search.status else {
                return
            }
            pagination.tracks.append(laterSong)
            pagination.nextCursor = nil
            pagination.status = .idle
            $0.search.status = .loaded(pagination)
        }

        #expect(store.state.playback.queue.tracks == firstPage)

        await store.send(.search(.resultTapped(laterSong.id)))
        await store.receive(
            .search(.delegate(.trackTapped(laterSong, loadedResults: laterResults)))
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
                    tracks: laterResults,
                    targetTrackID: laterSong.id
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

        #expect(store.state.playback.queue.tracks == firstPage)
        guard
            case .queueReplacement(let replacement) =
                store.state.playback.pendingOperation
        else {
            Issue.record("Expected a pending queue replacement")
            return
        }
        #expect(replacement.tracks == laterResults)

        await store.send(.playback(.cancelPendingOperation)) {
            $0.playback.pendingOperation = nil
        }
    }

    @Test
    func providerSwitchRejectsSearchSelection() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
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
                    .trackTapped(
                        tracks[0],
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
            tracks: [],
            playbackOrder: PlaybackQueueOrder(trackIDs: []),
            currentTrackID: nil,
            repeatMode: .off,
            shuffleMode: .off
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
            tracks: [],
            playbackOrder: PlaybackQueueOrder(trackIDs: []),
            currentTrackID: nil,
            repeatMode: .off,
            shuffleMode: .off
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
                providerAccess: access,
                providerID: providerID
            ),
            playback: PlaybackFeature.State(
                providerID: providerID,
                queue: playbackQueue,
                status: playbackQueue.currentTrack == nil ? .idle : .playing,
                failure: nil,
                playbackEligibility: access.playbackEligibility,
                capabilities: .allEnabled,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: 0,
                    interaction: .idle
                ),
                pendingOperation: nil,
                pendingProviderReset: nil,
                isPlayerPresented: isPlayerPresented
            ),
            providerSwitch: providerSwitch
        )
    }

    private func makeTracks(prefix: String = "song") -> [Track] {
        [
            makeTrack(nativeID: "\(prefix)-1"),
            makeTrack(nativeID: "\(prefix)-2"),
            makeTrack(nativeID: "\(prefix)-3"),
        ]
    }

    private func makeTrack(nativeID: String) -> Track {
        Track(
            id: .init(providerID: providerID, nativeID: nativeID),
            title: nativeID,
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: 180
        )
    }
}
