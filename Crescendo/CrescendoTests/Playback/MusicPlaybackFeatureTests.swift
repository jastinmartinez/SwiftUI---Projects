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
            $0.status = .observing(snapshot)
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
            status: .loading(.idle)
        )

        await store.send(.snapshotReceived(snapshot)) {
            $0.status = .loading(snapshot)
        }
    }

    @Test
    func pollingSnapshotPreservesFailureUntilNextPlaybackAttempt() async {
        let (snapshots, continuation) = AsyncStream<MusicPlaybackSnapshot>.makeStream()
        let playCallCount = LockIsolated(0)
        let song = makeSong()
        let store = makeStore(song: song) {
            $0.musicProvider.playbackSnapshots = { snapshots }
            $0.musicProvider.play = { _ in
                let shouldFail = playCallCount.withValue { callCount in
                    callCount += 1
                    return callCount == 1
                }
                if shouldFail {
                    throw MusicProviderError.playbackFailed
                }
            }
        }

        await store.send(.task)
        await store.send(.playTapped) {
            $0.status = .loading(.idle)
        }
        await store.receive(.transportFailed(.playbackFailed)) {
            $0.status = .failed(
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
            $0.status = .failed(
                .playbackFailed,
                lastSnapshot: latestSnapshot
            )
        }

        await store.send(.playTapped) {
            $0.status = .loading(latestSnapshot)
        }
        await store.receive(.transportFinished) {
            $0.status = .observing(latestSnapshot)
        }

        let playingSnapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .playing,
            currentTime: 1
        )
        continuation.yield(playingSnapshot)
        continuation.finish()
        await store.receive(.snapshotReceived(playingSnapshot)) {
            $0.status = .observing(playingSnapshot)
        }
    }

    @Test
    func playForwardsTheSelectedItemID() async {
        let receivedItemID = LockIsolated<MusicItemID?>(nil)
        let song = makeSong()
        let store = makeStore(song: song) {
            $0.musicProvider.play = { itemID in
                receivedItemID.withValue { $0 = itemID }
            }
        }

        await store.send(.playTapped) {
            $0.status = .loading(.idle)
        }
        await store.receive(.transportFinished) {
            $0.status = .observing(.idle)
        }

        #expect(receivedItemID.value == song.id)
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
            $0.status = .observing(snapshot)
        }
    }

    @Test
    func ineligibleAccountCannotStartPlayback() async {
        let song = makeSong()
        let store = makeStore(
            song: song,
            playbackEligibility: .ineligible
        ) {
            $0.musicProvider.play = { _ in
                Issue.record("Playback must remain gated for an ineligible account")
            }
        }

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
    func playFailureRetainsSelection() async {
        let song = makeSong()
        let store = makeStore(song: song) {
            $0.musicProvider.play = { _ in
                throw MusicProviderError.playbackFailed
            }
        }

        await store.send(.playTapped) {
            $0.status = .loading(.idle)
        }
        await store.receive(.transportFailed(.playbackFailed)) {
            $0.status = .failed(
                .playbackFailed,
                lastSnapshot: .idle
            )
        }

        #expect(store.state.selectedSong == song)
    }

    // MARK: - Helpers

    private func makeStore(
        song: SongSummary,
        status: MusicPlaybackFeature.Status = .observing(.idle),
        playbackEligibility: CatalogPlaybackEligibility = .eligible,
        capabilities: MusicProviderCapabilities = .allEnabled,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<MusicPlaybackFeature> {
        TestStore(
            initialState: MusicPlaybackFeature.State(
                selectedSong: song,
                status: status,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities
            )
        ) {
            MusicPlaybackFeature()
        } withDependencies: {
            configureDependencies(&$0)
        }
    }

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            artworkURL: nil
        )
    }
}
