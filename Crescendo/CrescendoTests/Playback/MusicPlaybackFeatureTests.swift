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
        await store.receive(.transportFinished)

        #expect(stopCallCount.value == 1)
    }

    @Test
    func supportedSeekForwardsTheRequestedTime() async {
        let receivedTime = LockIsolated<TimeInterval?>(nil)
        let store = makeStore(song: makeSong()) {
            $0.musicProvider.seek = { time in
                receivedTime.withValue { $0 = time }
            }
        }

        await store.send(.seekRequested(30))
        await store.receive(.transportFinished)

        #expect(receivedTime.value == 30)
    }

    @Test
    func unsupportedSeekDoesNothing() async {
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: false,
            supportsQueueReplacement: true
        )
        let store = makeStore(
            song: makeSong(),
            capabilities: capabilities
        ) {
            $0.musicProvider.seek = { _ in
                Issue.record("Seeking must remain gated when unsupported")
            }
        }

        await store.send(.seekRequested(30))
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
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<MusicPlaybackFeature> {
        TestStore(
            initialState: MusicPlaybackFeature.State(
                selectedSong: song,
                phase: phase,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities
            )
        ) {
            MusicPlaybackFeature()
        } withDependencies: {
            configureDependencies(&$0)
        }
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
