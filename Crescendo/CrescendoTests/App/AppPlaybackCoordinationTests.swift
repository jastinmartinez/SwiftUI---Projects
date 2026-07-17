import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func musicStartPreservesLatestSnapshotWhilePlayInFlight() async {
        let song = makeSong()
        let latestSnapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .paused,
            currentTime: 42
        )
        let (playStarted, playStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePlay, resumePlayContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: makeState(song: song)) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.play = { _ in
                playStartedContinuation.yield()
                for await _ in resumePlay { break }
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackTransition = .startingMusic(song.id)
        }
        await store.receive(\.musicPlayback.playbackStartAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }

        var playStartedIterator = playStarted.makeAsyncIterator()
        _ = await playStartedIterator.next()
        await store.send(.musicPlayback(.snapshotReceived(latestSnapshot))) {
            $0.musicPlayback.phase = .loading(latestSnapshot)
        }

        resumePlayContinuation.yield()
        resumePlayContinuation.finish()
        await store.receive(.musicStartSucceeded(song.id)) {
            $0.playbackTransition = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(latestSnapshot)
        }
        playStartedContinuation.finish()
    }

    @Test
    func failedMusicStartFinishesChildRequestWithProviderError() async {
        let song = makeSong()
        let store = TestStore(initialState: makeState(song: song)) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.play = { _ in
                throw MusicProviderError.network
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackTransition = .startingMusic(song.id)
        }
        await store.receive(\.musicPlayback.playbackStartAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }
        await store.receive(.musicStartFailed(song.id, .network)) {
            $0.playbackTransition = nil
        }
        await store.receive(\.musicPlayback.transportFailed) {
            $0.musicPlayback.phase = .failed(.network, lastSnapshot: .idle)
        }
    }

    @Test
    func overlappingPlaybackRequestsDoNotStartAnotherTransition() async {
        let events = LockIsolated<[String]>([])
        let song = makeSong()
        let otherSongID = MusicItemID(providerID: "fake", nativeID: "2")
        let (playStarted, playStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePlay, resumePlayContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: makeState(song: song)) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.play = { itemID in
                events.withValue { $0.append("play-\(itemID.nativeID)") }
                playStartedContinuation.yield()
                for await _ in resumePlay { break }
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackTransition = .startingMusic(song.id)
        }
        await store.receive(\.musicPlayback.playbackStartAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }

        var playStartedIterator = playStarted.makeAsyncIterator()
        _ = await playStartedIterator.next()
        await store.send(.musicPlayback(.delegate(.playRequested(otherSongID))))
        #expect(store.state.playbackTransition == .startingMusic(song.id))
        #expect(events.value == ["play-1"])

        resumePlayContinuation.yield()
        resumePlayContinuation.finish()
        await store.receive(.musicStartSucceeded(song.id)) {
            $0.playbackTransition = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(.idle)
        }

        #expect(events.value == ["play-1"])
        playStartedContinuation.finish()
    }

    @Test
    func staleMusicCompletionsForDifferentItemAreIgnored() async {
        let song = makeSong()
        let staleItemID = MusicItemID(providerID: "fake", nativeID: "stale")
        var state = makeState(song: song)
        state.musicPlayback.phase = .loading(.idle)
        state.playbackTransition = .startingMusic(song.id)
        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.musicStartSucceeded(staleItemID))
        await store.send(.musicStartFailed(staleItemID, .network))

        #expect(store.state.playbackTransition == .startingMusic(song.id))
        #expect(store.state.musicPlayback.phase == .loading(.idle))
    }

    // MARK: - Helpers

    private func makeState(song: SongSummary) -> AppFeature.State {
        AppFeature.State(
            providerConnection: ProviderConnectionFeature.State(
                providers: [.appleMusic],
                connection: .connected(
                    providerID: .appleMusic,
                    access: MusicProviderAccess(
                        authorization: .authorized,
                        playbackEligibility: .eligible
                    )
                )
            ),
            search: SearchFeature.State(
                query: "",
                phase: .idle,
                playbackEligibility: .eligible
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: song,
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: .allEnabled
            ),
            isPlayerPresented: false,
            pendingProviderID: nil,
            providerSwitchRequestID: nil,
            playbackTransition: nil
        )
    }

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
