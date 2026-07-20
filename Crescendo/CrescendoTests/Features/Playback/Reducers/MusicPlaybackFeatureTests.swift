import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct MusicPlaybackFeatureTests {
    @Test
    func taskConsumesPlaybackSnapshots() async {
        let song = makeSong()
        let snapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .playing,
            currentTime: 12
        )
        let store = makeStore(song: song) {
            $0.musicProvider.playbackSnapshots = {
                AsyncStream { continuation in
                    continuation.yield(snapshot)
                    continuation.finish()
                }
            }
        }

        await store.send(.task)
        await store.receive(.snapshotReceived(snapshot)) {
            $0.phase = .observing(snapshot)
        }
    }

    @Test
    func pollingSnapshotDoesNotFinishLoadingCommand() async {
        let song = makeSong()
        let snapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .playing,
            currentTime: 1
        )
        let store = makeStore(
            song: song,
            phase: .loading(.idle)
        )

        await store.send(.snapshotReceived(snapshot)) {
            $0.phase = .loading(snapshot)
        }
    }

    @Test
    func pollingSnapshotPreservesFailureUntilNextPlaybackAttempt() async {
        let (snapshots, continuation) = AsyncStream<MusicPlaybackSnapshot>.makeStream()
        let song = makeSong()
        let store = makeStore(song: song) {
            $0.musicProvider.playbackSnapshots = { snapshots }
        }

        await store.send(.task)
        await store.send(.playTapped)
        await store.receive(.delegate(.playRequested(song.id)))
        await store.send(.playbackCommandAccepted) {
            $0.phase = .loading(.idle)
        }
        await store.send(.transportFailed(.playbackFailed)) {
            $0.phase = .failed(
                .playbackFailed,
                lastSnapshot: .idle
            )
        }

        let latestSnapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .paused,
            currentTime: 4
        )
        continuation.yield(latestSnapshot)
        await store.receive(.snapshotReceived(latestSnapshot)) {
            $0.phase = .failed(
                .playbackFailed,
                lastSnapshot: latestSnapshot
            )
        }

        await store.send(.playTapped)
        await store.receive(.delegate(.resumeRequested(song.id)))
        await store.send(.playbackCommandAccepted) {
            $0.phase = .loading(latestSnapshot)
        }
        await store.send(.transportFinished) {
            $0.phase = .observing(latestSnapshot)
        }

        let playingSnapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .playing,
            currentTime: 1
        )
        continuation.yield(playingSnapshot)
        continuation.finish()
        await store.receive(.snapshotReceived(playingSnapshot)) {
            $0.phase = .observing(playingSnapshot)
        }
    }

    @Test
    func eligiblePlayDelegatesWithoutCallingProvider() async {
        let playCallCount = LockIsolated(0)
        let song = makeSong()
        let store = makeStore(song: song) {
            $0.musicProvider.play = { _ in
                playCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.playTapped)
        await store.receive(.delegate(.playRequested(song.id)))

        #expect(playCallCount.value == 0)
        #expect(store.state.phase == .observing(.idle))
    }

    @Test
    func pausedCurrentSongDelegatesResumeWithoutCallingProvider() async {
        let song = makeSong()
        let playCallCount = LockIsolated(0)
        let resumeCallCount = LockIsolated(0)
        let store = makeStore(
            song: song,
            phase: .observing(makeSnapshot(song: song, status: .paused))
        ) {
            $0.musicProvider.play = { _ in
                playCallCount.withValue { $0 += 1 }
            }
            $0.musicProvider.resume = {
                resumeCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.playTapped)
        await store.receive(.delegate(.resumeRequested(song.id)))

        #expect(playCallCount.value == 0)
        #expect(resumeCallCount.value == 0)
    }

    @Test
    func pausedCurrentSongCanResumeWithoutQueueReplacement() async {
        let song = makeSong()
        let store = makeStore(
            song: song,
            phase: .observing(makeSnapshot(song: song, status: .paused)),
            capabilities: makeResumeOnlyCapabilities()
        )

        #expect(store.state.canPlaySelectedSong)
        await store.send(.playTapped)
        await store.receive(.delegate(.resumeRequested(song.id)))
    }

    @Test
    func idleSongCannotPlayWithoutQueueReplacement() async {
        let store = makeStore(
            song: makeSong(),
            capabilities: makeResumeOnlyCapabilities()
        )

        #expect(!store.state.canPlaySelectedSong)
        await store.send(.playTapped)
    }

    @Test
    func stoppedCurrentSongDelegatesPlay() async {
        let song = makeSong()
        let store = makeStore(
            song: song,
            phase: .observing(makeSnapshot(song: song, status: .stopped))
        )

        await store.send(.playTapped)
        await store.receive(.delegate(.playRequested(song.id)))
    }

    @Test
    func pausedDifferentSongDelegatesPlay() async {
        let selectedSong = makeSong()
        let currentSong = makeSong(nativeID: "2")
        let store = makeStore(
            song: selectedSong,
            phase: .observing(
                makeSnapshot(song: currentSong, status: .paused)
            )
        )

        await store.send(.playTapped)
        await store.receive(.delegate(.playRequested(selectedSong.id)))
    }

    @Test
    func idleSnapshotDelegatesPlay() async {
        let song = makeSong()
        let store = makeStore(song: song)

        await store.send(.playTapped)
        await store.receive(.delegate(.playRequested(song.id)))
    }

    @Test
    func parentAcceptanceMovesMusicToLoading() async {
        let store = makeStore(song: makeSong())

        await store.send(.playbackCommandAccepted) {
            $0.phase = .loading(.idle)
        }
    }

    @Test
    func receivedSnapshotReplacesObservedPlaybackState() async {
        let song = makeSong()
        let snapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .playing,
            currentTime: 12
        )
        let store = makeStore(song: song)

        await store.send(.snapshotReceived(snapshot)) {
            $0.phase = .observing(snapshot)
        }
    }

    @Test
    func ineligibleAccountDoesNotDelegatePlayback() async {
        let store = makeStore(
            song: makeSong(),
            playbackEligibility: .ineligible
        )

        #expect(!store.state.canPlaySelectedSong)
        await store.send(.playTapped)
    }

    @Test
    func unsupportedPlaybackDoesNotDelegatePlayback() async {
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: false,
            supportsSeeking: true,
            supportsQueueReplacement: true
        )
        let store = makeStore(
            song: makeSong(),
            capabilities: capabilities
        )

        #expect(!store.state.canPlaySelectedSong)
        await store.send(.playTapped)
    }

    @Test
    func missingSelectionDoesNotDelegatePlayback() async {
        let store = makeStore(song: nil)

        #expect(!store.state.canPlaySelectedSong)
        await store.send(.playTapped)
    }

    @Test
    func pauseForwardsToTheProvider() async {
        let pauseCallCount = LockIsolated(0)
        let store = makeStore(song: makeSong()) {
            $0.musicProvider.pause = {
                pauseCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.pauseTapped)
        await store.receive(.transportFinished)

        #expect(pauseCallCount.value == 1)
    }

    @Test
    func stopForwardsToTheProvider() async {
        let stopCallCount = LockIsolated(0)
        let store = makeStore(song: makeSong()) {
            $0.musicProvider.stop = {
                stopCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.stopTapped)
        await store.receive(.timeline(.reset))
        await store.receive(.transportFinished)

        #expect(stopCallCount.value == 1)
    }

    @Test
    func differentSongSelectionResetsTimelineInteraction() async {
        let suspendedSeek = SuspendedSeekProbe()
        let selectedSong = makeSong()
        let nextSong = makeSong(nativeID: "2")
        let store = makeStore(song: selectedSong) {
            $0.musicProvider.seek = suspendedSeek.callAsFunction
        }
        await startSuspendedSeek(suspendedSeek, on: store)

        await store.send(
            .songTapped(
                nextSong,
                playbackEligibility: .ineligible
            )
        )
        await store.receive(.timeline(.reset)) {
            $0.timeline.interaction = .idle
        }
        #expect(suspendedSeek.cancellationObserved.value)
        #expect(store.state.selectedSong == selectedSong)

        await store.receive(
            .applySongSelection(
                nextSong,
                playbackEligibility: .ineligible
            )
        ) {
            $0.selectedSong = nextSong
            $0.playbackEligibility = .ineligible
        }

        suspendedSeek.fail(with: .network)
        await store.finish()
        #expect(store.state.selectedSong == nextSong)
        #expect(store.state.timeline.interaction == .idle)
    }

    @Test
    func sameSongSelectionPreservesTimelineInteraction() async {
        let suspendedSeek = SuspendedSeekProbe()
        let song = makeSong()
        let store = makeStore(song: song) {
            $0.musicProvider.seek = suspendedSeek.callAsFunction
        }
        await startSuspendedSeek(suspendedSeek, on: store)

        await store.send(
            .songTapped(song, playbackEligibility: .ineligible)
        ) {
            $0.playbackEligibility = .ineligible
        }
        #expect(!suspendedSeek.cancellationObserved.value)

        await store.send(.timeline(.reset)) {
            $0.timeline.interaction = .idle
        }
        suspendedSeek.succeed()
        await store.finish()
    }

    @Test
    func stopResetsTimelineInteraction() async {
        let suspendedSeek = SuspendedSeekProbe()
        let stopObservedCancellation = LockIsolated(false)
        let store = makeStore(song: makeSong()) {
            $0.musicProvider.seek = suspendedSeek.callAsFunction
            $0.musicProvider.stop = {
                stopObservedCancellation.withValue {
                    $0 = suspendedSeek.cancellationObserved.value
                }
            }
        }
        await startSuspendedSeek(suspendedSeek, on: store)

        await store.send(.stopTapped)
        await store.receive(.timeline(.reset)) {
            $0.timeline.interaction = .idle
        }
        #expect(suspendedSeek.cancellationObserved.value)
        await store.receive(.transportFinished)

        suspendedSeek.succeed()
        await store.finish()
        #expect(stopObservedCancellation.value)
        #expect(store.state.timeline.interaction == .idle)
    }

    @Test
    func timelineFailurePreservesLatestSnapshot() async {
        let song = makeSong()
        let snapshot = makeSnapshot(song: song, status: .playing)
        let store = makeStore(
            song: song,
            phase: .observing(snapshot)
        )

        await store.send(
            .timeline(.delegate(.transportFailed(.network)))
        ) {
            $0.phase = .failed(.network, lastSnapshot: snapshot)
        }
    }

    @Test(arguments: [
        MusicPlaybackTimelineFeature.Interaction.dragging(position: 30),
        .seeking(requestID: UUID(0), position: 30),
    ])
    func snapshotDuringInteractionPreservesTimelineInteraction(
        interaction: MusicPlaybackTimelineFeature.Interaction
    ) async {
        let song = makeSong()
        let snapshot = makeSnapshot(song: song, status: .playing)
        let store = makeStore(
            song: song,
            timelineInteraction: interaction
        )

        await store.send(.snapshotReceived(snapshot)) {
            $0.phase = .observing(snapshot)
        }

        #expect(store.state.timeline.interaction == interaction)
    }

    @Test
    func acceptedPlayFailureRetainsSelection() async {
        let song = makeSong()
        let store = makeStore(song: song)

        await store.send(.playbackCommandAccepted) {
            $0.phase = .loading(.idle)
        }
        await store.send(.transportFailed(.playbackFailed)) {
            $0.phase = .failed(
                .playbackFailed,
                lastSnapshot: .idle
            )
        }

        #expect(store.state.selectedSong == song)
    }

    // MARK: - Helpers

    private func makeStore(
        song: SongSummary?,
        phase: MusicPlaybackFeature.Phase = .observing(.idle),
        playbackEligibility: CatalogPlaybackEligibility = .eligible,
        capabilities: MusicProviderCapabilities = .allEnabled,
        timelineInteraction: MusicPlaybackTimelineFeature.Interaction = .idle,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<MusicPlaybackFeature> {
        TestStore(
            initialState: MusicPlaybackFeature.State(
                selectedSong: song,
                phase: phase,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities,
                timeline: MusicPlaybackTimelineFeature.State(
                    interaction: timelineInteraction
                )
            )
        ) {
            MusicPlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            configureDependencies(&$0)
        }
    }

    private func startSuspendedSeek(
        _ suspendedSeek: SuspendedSeekProbe,
        on store: TestStoreOf<MusicPlaybackFeature>
    ) async {
        await store.send(.timeline(.positionChanged(30))) {
            $0.timeline.interaction = .dragging(position: 30)
        }
        await store.send(.timeline(.dragEnded)) {
            $0.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 30
            )
        }
        await suspendedSeek.waitUntilStarted()
    }

    private func makeSnapshot(
        song: SongSummary,
        status: MusicPlaybackStatus
    ) -> MusicPlaybackSnapshot {
        MusicPlaybackSnapshot(
            currentItem: song,
            status: status,
            currentTime: 42
        )
    }

    private func makeResumeOnlyCapabilities() -> MusicProviderCapabilities {
        MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: false
        )
    }

    private func makeSong(nativeID: String = "1") -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: nativeID),
            title: "Song",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
