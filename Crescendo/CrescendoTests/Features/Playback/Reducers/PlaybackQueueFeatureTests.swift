import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackQueueFeatureTests {
    @Test
    func replacementStoresSourceOrderAndSelectsTheRequestedTrack() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore()

        await store.send(.replace(queue, startingAt: tracks[1].id)) {
            $0.tracks = queue
            $0.playbackOrder = PlaybackQueueOrder(
                trackIDs: tracks.map(\.id)
            )
            $0.currentTrackID = tracks[1].id
        }

        #expect(store.state.currentTrack == tracks[1])
    }

    @Test
    func replacementResetsRepeatAndShuffleToOff() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore(
            tracks: tracks,
            orderedTrackIDs: tracks.reversed().map(\.id),
            currentTrackID: tracks[0].id,
            repeatMode: .one,
            shuffleMode: .tracks
        )

        await store.send(.replace(queue, startingAt: tracks[0].id)) {
            $0.playbackOrder = PlaybackQueueOrder(
                trackIDs: tracks.map(\.id)
            )
            $0.repeatMode = .off
            $0.shuffleMode = .off
        }
    }

    @Test(arguments: [
        TrackID(providerID: "fake", nativeID: "unknown"),
        TrackID(providerID: "other", nativeID: "1"),
    ])
    func unknownStartingTrackLeavesStateUnchanged(
        startingTrackID: TrackID
    ) async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore()
        let initialState = store.state

        await store.send(.replace(queue, startingAt: startingTrackID))

        #expect(store.state == initialState)
    }

    @Test
    func confirmedTrackAcceptsOnlyAKnownIdentity() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        )

        await store.send(.currentTrackConfirmed(tracks[1].id)) {
            $0.currentTrackID = tracks[1].id
        }
        await store.send(
            .currentTrackConfirmed(
                TrackID(providerID: "fake", nativeID: "unknown")
            )
        )

        #expect(store.state.currentTrackID == tracks[1].id)
    }

    @Test
    func previousAndNextRequestTheAdjacentTrackWithoutMutatingState() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[1].id
        )

        await store.send(.previousTapped)
        await store.receive(.delegate(.transitionRequested(tracks[0].id)))
        await store.send(.nextTapped)
        await store.receive(.delegate(.transitionRequested(tracks[2].id)))

        #expect(store.state.currentTrackID == tracks[1].id)
        #expect(store.state.tracks == IdentifiedArray(uniqueElements: tracks))
    }

    @Test
    func previousAtTheFirstTrackAndNextAtTheFinalTrackRequestNothing() async {
        let tracks = makeTracks()
        let firstStore = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        )
        let finalStore = makeStore(
            tracks: tracks,
            currentTrackID: tracks[2].id
        )

        await firstStore.send(.previousTapped)
        await finalStore.send(.nextTapped)
    }

    @Test(arguments: [
        PlaybackRepeatMode.off,
        .all,
        .one,
    ])
    func manualNavigationStaysBoundedForEveryRepeatMode(
        repeatMode: PlaybackRepeatMode
    ) async {
        let tracks = makeTracks()
        let firstStore = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: repeatMode
        )
        let finalStore = makeStore(
            tracks: tracks,
            currentTrackID: tracks[2].id,
            repeatMode: repeatMode
        )

        await firstStore.send(.previousTapped)
        await finalStore.send(.nextTapped)

        #expect(firstStore.state.currentTrackID == tracks[0].id)
        #expect(finalStore.state.currentTrackID == tracks[2].id)
    }

    @Test
    func completionWithRepeatOffStopsAtTheFinalTrack() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[2].id,
            repeatMode: .off
        )

        await store.send(.currentTrackCompleted(tracks[2].id))
    }

    @Test
    func completionWithRepeatOffAdvancesInsideTheQueue() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .off
        )

        await store.send(.currentTrackCompleted(tracks[0].id))
        await store.receive(.delegate(.transitionRequested(tracks[1].id)))
    }

    @Test
    func completionWithRepeatAllWrapsToTheFirstTrack() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[2].id,
            repeatMode: .all
        )

        await store.send(.currentTrackCompleted(tracks[2].id))
        await store.receive(.delegate(.transitionRequested(tracks[0].id)))
    }

    @Test
    func completionWithRepeatOneRepeatsTheCurrentTrack() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[1].id,
            repeatMode: .one
        )

        await store.send(.currentTrackCompleted(tracks[1].id))
        await store.receive(.delegate(.transitionRequested(tracks[1].id)))
    }

    @Test
    func staleCompletionRequestsNothing() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .all
        )

        await store.send(.currentTrackCompleted(tracks[2].id))
    }

    @Test
    func repeatTappedCyclesOffThenAllThenOne() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .off
        )

        await store.send(.repeatTapped) { $0.repeatMode = .all }
        await store.send(.repeatTapped) { $0.repeatMode = .one }
        await store.send(.repeatTapped) { $0.repeatMode = .off }
    }

    @Test
    func enablingShuffleAdoptsTheInjectedOrderAndKeepsTheCurrentTrack() async {
        let tracks = makeTracks()
        let shuffled = [tracks[2].id, tracks[0].id, tracks[1].id]
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            shuffleMode: .off
        ) {
            $0.playbackShuffle.shuffle = { _ in shuffled }
        }

        await store.send(.shuffleTapped) {
            $0.playbackOrder = PlaybackQueueOrder(trackIDs: shuffled)
            $0.shuffleMode = .tracks
        }

        #expect(store.state.currentTrackID == tracks[0].id)
    }

    @Test
    func disablingShuffleRestoresTheCanonicalOrder() async {
        let tracks = makeTracks()
        let calls = LockIsolated(0)
        let store = makeStore(
            tracks: tracks,
            orderedTrackIDs: [tracks[2].id, tracks[0].id, tracks[1].id],
            currentTrackID: tracks[0].id,
            shuffleMode: .tracks
        ) {
            $0.playbackShuffle.shuffle = { trackIDs in
                calls.withValue { $0 += 1 }
                return trackIDs
            }
        }

        await store.send(.shuffleTapped) {
            $0.playbackOrder = PlaybackQueueOrder(
                trackIDs: tracks.map(\.id)
            )
            $0.shuffleMode = .off
        }

        #expect(calls.value == 0)
    }

    @Test(arguments: [
        [0, 0, 1],
        [0, 1],
        [0, 1, 2, 2],
    ])
    func invalidShuffleResultIsRejected(indices: [Int]) async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            shuffleMode: .off
        ) {
            $0.playbackShuffle.shuffle = { _ in indices.map { tracks[$0].id } }
        }

        await store.send(.shuffleTapped)

        #expect(store.state.shuffleMode == .off)
        #expect(
            store.state.playbackOrder
                == PlaybackQueueOrder(trackIDs: tracks.map(\.id))
        )
    }

    @Test
    func upNextFollowsThePlaybackOrderAfterTheCurrentTrack() async {
        let tracks = makeTracks()
        let shuffled = [tracks[2].id, tracks[0].id, tracks[1].id]
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            shuffleMode: .off
        ) {
            $0.playbackShuffle.shuffle = { _ in shuffled }
        }

        #expect(store.state.upNextTrackIDs == [tracks[1].id, tracks[2].id])

        await store.send(.shuffleTapped) {
            $0.playbackOrder = PlaybackQueueOrder(trackIDs: shuffled)
            $0.shuffleMode = .tracks
        }

        #expect(store.state.upNextTrackIDs == [tracks[1].id])
    }

    @Test
    func resetClearsTheQueueOrderCurrentTrackAndModes() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            orderedTrackIDs: tracks.reversed().map(\.id),
            currentTrackID: tracks[0].id,
            repeatMode: .all,
            shuffleMode: .tracks
        )

        await store.send(.reset) {
            $0.tracks = []
            $0.playbackOrder = PlaybackQueueOrder(trackIDs: [])
            $0.currentTrackID = nil
            $0.repeatMode = .off
            $0.shuffleMode = .off
        }

        #expect(store.state.currentTrack == nil)
        #expect(store.state.upNextTrackIDs.isEmpty)
    }

    // MARK: - Helpers

    private func makeStore(
        tracks: [Track] = [],
        orderedTrackIDs: [TrackID]? = nil,
        currentTrackID: TrackID? = nil,
        repeatMode: PlaybackRepeatMode = .off,
        shuffleMode: PlaybackShuffleMode = .off,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackQueueFeature> {
        TestStore(
            initialState: PlaybackQueueFeature.State(
                tracks: .init(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: orderedTrackIDs ?? tracks.map(\.id)
                ),
                currentTrackID: currentTrackID,
                repeatMode: repeatMode,
                shuffleMode: shuffleMode
            )
        ) {
            PlaybackQueueFeature()
        } withDependencies: {
            configureDependencies(&$0)
        }
    }

    private func makeTracks() -> [Track] {
        [
            makeTrack(nativeID: "1"),
            makeTrack(nativeID: "2"),
            makeTrack(nativeID: "3"),
        ]
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
