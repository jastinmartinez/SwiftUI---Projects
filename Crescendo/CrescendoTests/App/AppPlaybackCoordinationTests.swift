import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func searchSelectionRoutesExactLoadedResultsIntoPlayback() async {
        let songs = makeSongs()
        let loadedResults = IdentifiedArray(uniqueElements: songs)
        let calls = LockIsolated<[MusicItemID]>([])
        let store = makeStore {
            $0.playbackControl.playQueue = { itemIDs, _ in
                calls.withValue { $0 = itemIDs }
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
        ) {
            $0.isPlayerPresented = true
        }
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
        await store.receive(
            .playback(.queueReplacementSucceeded(requestID: UUID(0)))
        ) {
            $0.playback.pendingOperation = nil
            $0.playback.status = .playing
        }
        await store.receive(
            .playback(
                .queue(
                    .replace(
                        loadedResults,
                        startingAt: songs[1].id
                    )
                )
            )
        ) {
            $0.playback.queue.songs = loadedResults
            $0.playback.queue.currentItemID = songs[1].id
        }
        await store.receive(.playback(.timeline(.reset)))

        #expect(calls.value == Array(loadedResults.ids))
    }

    @Test
    func laterSelectionDoesNotReopenDismissedPlayer() async {
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
            $0.playbackControl.playQueue = { _, _ in }
        }
        store.exhaustivity = .off

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

        #expect(!store.state.isPlayerPresented)
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

    @Test
    func ineligibleSelectionOpensPlayerWithoutCallingPlayback() async {
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
        ) {
            $0.isPlayerPresented = true
        }
        await store.receive(
            .playback(
                .selectionReceived(
                    song,
                    loadedResults: loadedResults,
                    providerID: providerID,
                    playbackEligibility: .ineligible
                )
            )
        )

        #expect(calls.value == 0)
        #expect(store.state.playback.queue.currentItem == nil)
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
                pendingOperation: nil
            ),
            isPlayerPresented: isPlayerPresented,
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
