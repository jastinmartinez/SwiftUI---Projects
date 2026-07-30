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
            $0.current = PlaybackQueue(
                tracks: queue,
                startingAt: tracks[1].id
            )
        }

        #expect(store.state.current?.currentTrack == tracks[1])
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
            $0.current = makeConfirmedQueue(
                tracks,
                startingAt: tracks[0].id
            )
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
    func selectionFreezesAReplacementAndRequestsPlayback() async {
        let confirmedTracks = makeTracks(prefix: "confirmed")
        let selectedTracks = makeTracks(prefix: "selected")
        let loadedResults = IdentifiedArray(uniqueElements: selectedTracks)
        let store = makeStore(
            tracks: confirmedTracks,
            currentTrackID: confirmedTracks[0].id
        )

        await store.send(
            .selectionRequested(
                selectedTracks[1].id,
                loadedResults: loadedResults
            )
        ) {
            $0.pendingChanges = .init(
                active: replacementChange(
                    loadedResults,
                    startingAt: selectedTracks[1].id
                ),
                followUp: nil
            )
        }
        await store.receive(
            .delegate(.transitionRequested(selectedTracks[1].id))
        )

        #expect(store.state.current?.currentTrack == confirmedTracks[0])
        #expect(store.state.pendingTrack == selectedTracks[1])
    }

    @Test
    func latestSelectionReplacesOnlyThePendingFollowUp() async {
        let firstTracks = makeTracks(prefix: "first")
        let firstResults = IdentifiedArray(uniqueElements: firstTracks)
        let latestTracks = makeTracks(prefix: "latest")
        let latestResults = IdentifiedArray(uniqueElements: latestTracks)
        let store = makeStore()

        await store.send(
            .selectionRequested(
                firstTracks[1].id,
                loadedResults: firstResults
            )
        ) {
            $0.pendingChanges = .init(
                active: replacementChange(
                    firstResults,
                    startingAt: firstTracks[1].id
                ),
                followUp: nil
            )
        }
        await store.receive(
            .delegate(.transitionRequested(firstTracks[1].id))
        )

        await store.send(
            .selectionRequested(
                latestTracks[2].id,
                loadedResults: latestResults
            )
        ) {
            $0.pendingChanges?.followUp = replacementChange(
                latestResults,
                startingAt: latestTracks[2].id
            )
        }
        await store.receive(
            .delegate(.transitionRequested(latestTracks[2].id))
        )

        #expect(store.state.pendingTrack == latestTracks[2])
    }

    @Test
    func confirmingTheActiveReplacementPromotesItsFollowUp() async {
        let firstTracks = makeTracks(prefix: "first")
        let firstResults = IdentifiedArray(uniqueElements: firstTracks)
        let latestTracks = makeTracks(prefix: "latest")
        let latestResults = IdentifiedArray(uniqueElements: latestTracks)
        let store = makeStore()

        await store.send(
            .selectionRequested(
                firstTracks[1].id,
                loadedResults: firstResults
            )
        ) {
            $0.pendingChanges = .init(
                active: replacementChange(
                    firstResults,
                    startingAt: firstTracks[1].id
                ),
                followUp: nil
            )
        }
        await store.receive(
            .delegate(.transitionRequested(firstTracks[1].id))
        )
        await store.send(
            .selectionRequested(
                latestTracks[2].id,
                loadedResults: latestResults
            )
        ) {
            $0.pendingChanges?.followUp = replacementChange(
                latestResults,
                startingAt: latestTracks[2].id
            )
        }
        await store.receive(
            .delegate(.transitionRequested(latestTracks[2].id))
        )

        await store.send(.pendingChangeConfirmed(firstTracks[1].id)) {
            $0.current = makeConfirmedQueue(
                firstResults,
                startingAt: firstTracks[1].id
            )
            $0.pendingChanges = .init(
                active: replacementChange(
                    latestResults,
                    startingAt: latestTracks[2].id
                ),
                followUp: nil
            )
        }

        #expect(store.state.pendingTrack == latestTracks[2])
    }

    @Test
    func confirmingTheSupersedingReplacementDiscardsTheAbandonedOne()
        async
    {
        let firstTracks = makeTracks(prefix: "first")
        let firstResults = IdentifiedArray(uniqueElements: firstTracks)
        let latestTracks = makeTracks(prefix: "latest")
        let latestResults = IdentifiedArray(uniqueElements: latestTracks)
        let store = makeStore()

        await store.send(
            .selectionRequested(
                firstTracks[1].id,
                loadedResults: firstResults
            )
        ) {
            $0.pendingChanges = .init(
                active: replacementChange(
                    firstResults,
                    startingAt: firstTracks[1].id
                ),
                followUp: nil
            )
        }
        await store.receive(
            .delegate(.transitionRequested(firstTracks[1].id))
        )
        await store.send(
            .selectionRequested(
                latestTracks[2].id,
                loadedResults: latestResults
            )
        ) {
            $0.pendingChanges?.followUp = replacementChange(
                latestResults,
                startingAt: latestTracks[2].id
            )
        }
        await store.receive(
            .delegate(.transitionRequested(latestTracks[2].id))
        )

        await store.send(.pendingChangeConfirmed(latestTracks[2].id)) {
            $0.current = makeConfirmedQueue(
                latestResults,
                startingAt: latestTracks[2].id
            )
            $0.pendingChanges = nil
        }
    }

    @Test
    func navigationConfirmationPreservesQueueOrderAndModes() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .one,
            shuffleMode: .tracks
        )

        await store.send(.nextTapped) {
            $0.pendingChanges = .init(
                active: .navigation(to: tracks[1].id),
                followUp: nil
            )
        }
        await store.receive(.delegate(.transitionRequested(tracks[1].id)))
        await store.send(.pendingChangeConfirmed(tracks[1].id)) {
            $0.current = $0.current?.navigating(
                to: tracks[1].id
            )
            $0.pendingChanges = nil
        }

        #expect(
            store.state.current?.playbackOrder
                == PlaybackQueueOrder(trackIDs: tracks.map(\.id))
        )
        #expect(store.state.current?.repeatMode == .one)
        #expect(store.state.current?.shuffleMode == .tracks)
    }

    @Test
    func discardingTheFollowUpKeepsTheActivePendingChange() async {
        let firstTracks = makeTracks(prefix: "first")
        let firstResults = IdentifiedArray(uniqueElements: firstTracks)
        let latestTracks = makeTracks(prefix: "latest")
        let latestResults = IdentifiedArray(uniqueElements: latestTracks)
        let store = makeStore()

        await store.send(
            .selectionRequested(
                firstTracks[1].id,
                loadedResults: firstResults
            )
        ) {
            $0.pendingChanges = .init(
                active: replacementChange(
                    firstResults,
                    startingAt: firstTracks[1].id
                ),
                followUp: nil
            )
        }
        await store.receive(
            .delegate(.transitionRequested(firstTracks[1].id))
        )
        await store.send(
            .selectionRequested(
                latestTracks[2].id,
                loadedResults: latestResults
            )
        ) {
            $0.pendingChanges?.followUp = replacementChange(
                latestResults,
                startingAt: latestTracks[2].id
            )
        }
        await store.receive(
            .delegate(.transitionRequested(latestTracks[2].id))
        )

        await store.send(.pendingFollowUpDiscarded) {
            $0.pendingChanges?.followUp = nil
        }

        #expect(store.state.pendingTrack == firstTracks[1])
    }

    @Test
    func discardingPendingChangesPreservesTheConfirmedQueue() async {
        let confirmedTracks = makeTracks(prefix: "confirmed")
        let selectedTracks = makeTracks(prefix: "selected")
        let loadedResults = IdentifiedArray(uniqueElements: selectedTracks)
        let store = makeStore(
            tracks: confirmedTracks,
            currentTrackID: confirmedTracks[0].id
        )

        await store.send(
            .selectionRequested(
                selectedTracks[1].id,
                loadedResults: loadedResults
            )
        ) {
            $0.pendingChanges = .init(
                active: replacementChange(
                    loadedResults,
                    startingAt: selectedTracks[1].id
                ),
                followUp: nil
            )
        }
        await store.receive(
            .delegate(.transitionRequested(selectedTracks[1].id))
        )
        await store.send(.pendingChangesDiscarded) {
            $0.pendingChanges = nil
        }

        #expect(store.state.current?.currentTrack == confirmedTracks[0])
        #expect(
            store.state.current?.tracks
                == IdentifiedArray(uniqueElements: confirmedTracks)
        )
    }

    @Test
    func confirmedTrackAcceptsOnlyAKnownIdentity() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        )

        await store.send(.currentTrackConfirmed(tracks[1].id)) {
            $0.current = $0.current?.navigating(
                to: tracks[1].id
            )
        }
        await store.send(
            .currentTrackConfirmed(
                TrackID(providerID: "fake", nativeID: "unknown")
            )
        )

        #expect(store.state.current?.currentTrackID == tracks[1].id)
    }

    @Test
    func previousAndNextRequestAdjacentTracksWithoutChangingConfirmedQueue()
        async
    {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[1].id
        )

        await store.send(.previousTapped) {
            $0.pendingChanges = .init(
                active: .navigation(to: tracks[0].id),
                followUp: nil
            )
        }
        await store.receive(.delegate(.transitionRequested(tracks[0].id)))
        await store.send(.nextTapped) {
            $0.pendingChanges?.followUp = .navigation(to: tracks[2].id)
        }
        await store.receive(.delegate(.transitionRequested(tracks[2].id)))

        #expect(store.state.current?.currentTrackID == tracks[1].id)
        #expect(
            store.state.current?.tracks
                == IdentifiedArray(uniqueElements: tracks)
        )
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

        #expect(
            firstStore.state.current?.currentTrackID == tracks[0].id
        )
        #expect(
            finalStore.state.current?.currentTrackID == tracks[2].id
        )
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

        await store.send(.currentTrackCompleted(tracks[0].id)) {
            $0.pendingChanges = .init(
                active: .navigation(to: tracks[1].id),
                followUp: nil
            )
        }
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

        await store.send(.currentTrackCompleted(tracks[2].id)) {
            $0.pendingChanges = .init(
                active: .navigation(to: tracks[0].id),
                followUp: nil
            )
        }
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

        await store.send(.currentTrackCompleted(tracks[1].id)) {
            $0.pendingChanges = .init(
                active: .navigation(to: tracks[1].id),
                followUp: nil
            )
        }
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

        await store.send(.repeatTapped) {
            $0.current = $0.current?.cyclingRepeatMode()
        }
        await store.send(.repeatTapped) {
            $0.current = $0.current?.cyclingRepeatMode()
        }
        await store.send(.repeatTapped) {
            $0.current = $0.current?.cyclingRepeatMode()
        }
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
            $0.current = $0.current?.enablingShuffle(
                with: shuffled
            )
        }

        #expect(store.state.current?.currentTrackID == tracks[0].id)
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
            $0.current = $0.current?.disablingShuffle()
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

        #expect(store.state.current?.shuffleMode == .off)
        #expect(
            store.state.current?.playbackOrder
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

        #expect(
            store.state.current?.upNextTracks
                == [tracks[1], tracks[2]]
        )

        await store.send(.shuffleTapped) {
            $0.current = $0.current?.enablingShuffle(
                with: shuffled
            )
        }

        #expect(store.state.current?.upNextTracks == [tracks[1]])
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
            $0.current = nil
        }

        #expect(store.state.current == nil)
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
                current: makeConfirmedQueue(
                    tracks,
                    orderedTrackIDs: orderedTrackIDs,
                    currentTrackID: currentTrackID,
                    repeatMode: repeatMode,
                    shuffleMode: shuffleMode
                )
            )
        ) {
            PlaybackQueueFeature()
        } withDependencies: {
            configureDependencies(&$0)
        }
    }

    private func replacementChange(
        _ tracks: IdentifiedArrayOf<Track>,
        startingAt trackID: TrackID
    ) -> PlaybackQueueFeature.QueueChange {
        .replacement(
            makeConfirmedQueue(
                tracks,
                startingAt: trackID
            )
        )
    }

    private func makeConfirmedQueue(
        _ tracks: IdentifiedArrayOf<Track>,
        startingAt trackID: TrackID
    ) -> PlaybackQueue {
        guard
            let queue = PlaybackQueue(
                tracks: tracks,
                startingAt: trackID
            )
        else {
            preconditionFailure("Expected a valid playback queue fixture")
        }
        return queue
    }

    private func makeConfirmedQueue(
        _ tracks: [Track],
        startingAt trackID: TrackID
    ) -> PlaybackQueue {
        makeConfirmedQueue(
            IdentifiedArray(uniqueElements: tracks),
            startingAt: trackID
        )
    }

    private func makeConfirmedQueue(
        _ tracks: [Track],
        orderedTrackIDs: [TrackID]? = nil,
        currentTrackID: TrackID? = nil,
        repeatMode: PlaybackRepeatMode = .off,
        shuffleMode: PlaybackShuffleMode = .off
    ) -> PlaybackQueue? {
        guard !tracks.isEmpty else { return nil }
        guard let currentTrackID else {
            preconditionFailure(
                "A non-empty playback queue fixture needs a current track"
            )
        }
        let identifiedTracks = IdentifiedArray(uniqueElements: tracks)
        guard
            let queue = PlaybackQueue(
                tracks: identifiedTracks,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: orderedTrackIDs ?? tracks.map(\.id)
                ),
                currentTrackID: currentTrackID,
                repeatMode: repeatMode,
                shuffleMode: shuffleMode
            )
        else {
            preconditionFailure("Expected a valid playback queue fixture")
        }
        return queue
    }

    private func makeTracks(prefix: String = "") -> [Track] {
        [
            makeTrack(nativeID: "\(prefix)1"),
            makeTrack(nativeID: "\(prefix)2"),
            makeTrack(nativeID: "\(prefix)3"),
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
