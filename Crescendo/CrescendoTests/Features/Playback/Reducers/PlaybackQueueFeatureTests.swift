import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct PlaybackQueueFeatureTests {
    @Test
    func replacementStoresTheFrozenOrderAndStartingItem() async {
        let songs = makeSongs()
        let queue = IdentifiedArray(uniqueElements: songs)
        let store = makeStore()

        await store.send(.replace(queue, startingAt: songs[1].id)) {
            $0.songs = queue
            $0.currentItemID = songs[1].id
        }

        #expect(store.state.currentItem == songs[1])
    }

    @Test
    func observedQueueItemUpdatesTheCurrentIdentity() async {
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
        )

        await store.send(.currentItemObserved(songs[1].id)) {
            $0.currentItemID = songs[1].id
        }

        #expect(store.state.currentItem == songs[1])
    }

    @Test(arguments: [
        MusicItemID(providerID: "fake", nativeID: "unknown"),
        MusicItemID(providerID: "other", nativeID: "1"),
    ])
    func unknownObservedItemPreservesTheCurrentItem(
        observedItemID: MusicItemID
    ) async {
        let songs = makeSongs()
        let state = PlaybackQueueFeature.State(
            songs: .init(uniqueElements: songs),
            currentItemID: songs[0].id
        )
        let store = TestStore(initialState: state) {
            PlaybackQueueFeature()
        }

        await store.send(.currentItemObserved(observedItemID))

        #expect(store.state == state)
        #expect(store.state.currentItem == songs[0])
    }

    @Test
    func missingObservedItemPreservesTheCurrentItem() async {
        let songs = makeSongs()
        let state = PlaybackQueueFeature.State(
            songs: .init(uniqueElements: songs),
            currentItemID: songs[0].id
        )
        let store = TestStore(initialState: state) {
            PlaybackQueueFeature()
        }

        await store.send(.currentItemObserved(nil))

        #expect(store.state == state)
        #expect(store.state.currentItem == songs[0])
    }

    @Test
    func resetEmptiesTheQueueAndCurrentIdentity() async {
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
        )

        await store.send(.reset) {
            $0.songs = []
            $0.currentItemID = nil
        }

        #expect(store.state.currentItem == nil)
    }

    // MARK: - Helpers

    private func makeStore(
        songs: [SongSummary] = [],
        currentItemID: MusicItemID? = nil
    ) -> TestStoreOf<PlaybackQueueFeature> {
        TestStore(
            initialState: PlaybackQueueFeature.State(
                songs: .init(uniqueElements: songs),
                currentItemID: currentItemID
            )
        ) {
            PlaybackQueueFeature()
        }
    }

    private func makeSongs() -> [SongSummary] {
        [
            makeSong(nativeID: "1"),
            makeSong(nativeID: "2"),
            makeSong(nativeID: "3"),
        ]
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
