import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func playbackStartPreservesLatestSnapshotWhilePlayInFlight() async {
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
            $0.playbackStart = PlaybackStartFeature.State(itemID: song.id)
        }
        await store.receive(\.musicPlayback.playbackStartAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }
        await store.receive(.playbackStart(.start))

        var playStartedIterator = playStarted.makeAsyncIterator()
        _ = await playStartedIterator.next()
        await store.send(.musicPlayback(.snapshotReceived(latestSnapshot))) {
            $0.musicPlayback.phase = .loading(latestSnapshot)
        }

        resumePlayContinuation.yield()
        resumePlayContinuation.finish()
        await store.receive(.playbackStart(.playSucceeded))
        await store.receive(.playbackStart(.delegate(.succeeded(song.id)))) {
            $0.playbackStart = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(latestSnapshot)
        }
        playStartedContinuation.finish()
    }

    @Test
    func failedPlaybackStartFinishesChildRequestWithProviderError() async {
        let song = makeSong()
        let store = TestStore(initialState: makeState(song: song)) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.play = { _ in
                throw MusicProviderError.network
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackStart = PlaybackStartFeature.State(itemID: song.id)
        }
        await store.receive(\.musicPlayback.playbackStartAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }
        await store.receive(.playbackStart(.start))
        await store.receive(.playbackStart(.playFailed(.network)))
        await store.receive(
            .playbackStart(.delegate(.failed(song.id, .network)))
        ) {
            $0.playbackStart = nil
        }
        await store.receive(\.musicPlayback.transportFailed) {
            $0.musicPlayback.phase = .failed(.network, lastSnapshot: .idle)
        }
    }

    @Test
    func overlappingPlaybackRequestsDoNotStartAnotherOperation() async {
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
            $0.playbackStart = PlaybackStartFeature.State(itemID: song.id)
        }
        await store.receive(\.musicPlayback.playbackStartAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }
        await store.receive(.playbackStart(.start))

        var playStartedIterator = playStarted.makeAsyncIterator()
        _ = await playStartedIterator.next()
        await store.send(.musicPlayback(.delegate(.playRequested(otherSongID))))
        #expect(
            store.state.playbackStart
                == PlaybackStartFeature.State(itemID: song.id)
        )
        #expect(events.value == ["play-1"])

        resumePlayContinuation.yield()
        resumePlayContinuation.finish()
        await store.receive(.playbackStart(.playSucceeded))
        await store.receive(.playbackStart(.delegate(.succeeded(song.id)))) {
            $0.playbackStart = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(.idle)
        }

        #expect(events.value == ["play-1"])
        playStartedContinuation.finish()
    }

    @Test
    func stalePlaybackCompletionsForDifferentItemAreIgnored() async {
        let song = makeSong()
        let staleItemID = MusicItemID(providerID: "fake", nativeID: "stale")
        var state = makeState(song: song)
        state.musicPlayback.phase = .loading(.idle)
        state.playbackStart = PlaybackStartFeature.State(itemID: song.id)
        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.playbackStart(.delegate(.succeeded(staleItemID))))
        await store.send(
            .playbackStart(.delegate(.failed(staleItemID, .network)))
        )

        #expect(
            store.state.playbackStart
                == PlaybackStartFeature.State(itemID: song.id)
        )
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
                providerAccess: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: song,
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: .allEnabled
            ),
            isPlayerPresented: false,
            providerSwitch: nil,
            playbackStart: nil
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
