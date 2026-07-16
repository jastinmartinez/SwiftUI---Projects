import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func musicStartPausesVideoBeforeProviderPlayAndPreservesLatestSnapshot() async {
        let events = LockIsolated<[String]>([])
        let song = makeSong()
        let latestSnapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .paused,
            currentTime: 42
        )
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: makeState(song: song)) {
            AppFeature()
        } withDependencies: {
            $0.videoPlayback.pause = {
                events.withValue { $0.append("pause-video") }
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            }
            $0.musicProvider.play = { _ in
                events.withValue { $0.append("play-music") }
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackTransition = .startingMusic(song.id)
        }
        await store.receive(\.musicPlayback.playbackStartAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }

        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()
        await store.send(.musicPlayback(.snapshotReceived(latestSnapshot))) {
            $0.musicPlayback.phase = .loading(latestSnapshot)
        }
        #expect(events.value == ["pause-video"])

        resumePauseContinuation.yield()
        resumePauseContinuation.finish()
        await store.receive(.musicStartSucceeded(song.id)) {
            $0.playbackTransition = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(latestSnapshot)
        }

        #expect(events.value == ["pause-video", "play-music"])
        pauseStartedContinuation.finish()
    }

    @Test
    func openingVideoPausesMusicBeforePresentation() async {
        let song = makeSong()
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: makeState(song: song)) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.pause = {
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            }
        }

        await store.send(.openVideoButtonTapped) {
            $0.playbackTransition = .openingVideo
        }

        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()
        #expect(store.state.video == nil)

        resumePauseContinuation.yield()
        resumePauseContinuation.finish()
        await store.receive(\.openVideoSucceeded) {
            $0.playbackTransition = nil
            $0.video = makeVideoState()
        }
        pauseStartedContinuation.finish()
    }

    @Test
    func failedMusicPauseKeepsVideoClosed() async {
        let store = TestStore(initialState: makeState(song: makeSong())) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.pause = {
                throw MusicProviderError.playbackFailed
            }
        }

        await store.send(.openVideoButtonTapped) {
            $0.playbackTransition = .openingVideo
        }
        await store.receive(\.openVideoFailed) {
            $0.playbackTransition = nil
        }
        #expect(store.state.video == nil)
    }

    @Test
    func failedMusicStartFinishesChildRequestWithProviderError() async {
        let song = makeSong()
        let store = TestStore(initialState: makeState(song: song)) {
            AppFeature()
        } withDependencies: {
            $0.videoPlayback.pause = {}
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
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: makeState(song: song)) {
            AppFeature()
        } withDependencies: {
            $0.videoPlayback.pause = {
                events.withValue { $0.append("pause-video") }
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            }
            $0.musicProvider.pause = {
                events.withValue { $0.append("pause-music") }
            }
            $0.musicProvider.play = { itemID in
                events.withValue { $0.append("play-\(itemID.nativeID)") }
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackTransition = .startingMusic(song.id)
        }
        await store.receive(\.musicPlayback.playbackStartAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }

        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()
        await store.send(.openVideoButtonTapped)
        await store.send(.musicPlayback(.delegate(.playRequested(otherSongID))))
        #expect(store.state.playbackTransition == .startingMusic(song.id))
        #expect(events.value == ["pause-video"])

        resumePauseContinuation.yield()
        resumePauseContinuation.finish()
        await store.receive(.musicStartSucceeded(song.id)) {
            $0.playbackTransition = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(.idle)
        }

        #expect(events.value == ["pause-video", "play-1"])
        #expect(store.state.video == nil)
        pauseStartedContinuation.finish()
    }

    @Test
    func staleCompletionFromDifferentTransitionIsIgnored() async {
        let song = makeSong()
        var state = makeState(song: song)
        state.playbackTransition = .startingMusic(song.id)
        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.openVideoSucceeded)
        await store.send(.openVideoFailed)

        #expect(store.state.playbackTransition == .startingMusic(song.id))
        #expect(store.state.video == nil)
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

    @Test
    func closeRequestDuringMusicTransitionIsIgnored() async {
        let events = LockIsolated<[String]>([])
        let song = makeSong()
        var state = makeState(song: song)
        state.video = makeVideoState()
        state.playbackTransition = .startingMusic(song.id)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.videoPlayback.pause = {
                events.withValue { $0.append("pause-video") }
            }
            $0.videoPlayback.clear = {
                events.withValue { $0.append("clear-video") }
            }
        }

        await store.send(.closeVideoRequested)

        #expect(store.state.video == makeVideoState())
        #expect(store.state.videoCloseRequestID == nil)
        #expect(store.state.playbackTransition == .startingMusic(song.id))
        #expect(events.value.isEmpty)
    }

    @Test
    func musicStartDuringVideoCloseIsIgnored() async {
        let events = LockIsolated<[String]>([])
        let song = makeSong()
        var state = makeState(song: song)
        state.video = makeVideoState()
        state.videoCloseRequestID = UUID(0)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.videoPlayback.pause = {
                events.withValue { $0.append("pause-video") }
            }
            $0.musicProvider.play = { _ in
                events.withValue { $0.append("play-music") }
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id))))

        #expect(store.state.playbackTransition == nil)
        #expect(store.state.musicPlayback.phase == .observing(.idle))
        #expect(events.value.isEmpty)
    }

    @Test
    func openingVideoWithStaleCloseRequestIsIgnored() async {
        let events = LockIsolated<[String]>([])
        let song = makeSong()
        var state = makeState(song: song)
        state.videoCloseRequestID = UUID(0)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.pause = {
                events.withValue { $0.append("pause-music") }
            }
        }

        await store.send(.openVideoButtonTapped)

        #expect(store.state.video == nil)
        #expect(store.state.playbackTransition == nil)
        #expect(events.value.isEmpty)
    }

    // MARK: - Helpers

    private func makeState(song: SongSummary) -> AppFeature.State {
        AppFeature.State(
            registeredProviders: [.appleMusic],
            activeProviderID: "apple-music",
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
            video: nil,
            videoCloseRequestID: nil,
            playbackTransition: nil
        )
    }

    private func makeVideoState() -> VideoPlaybackFeature.State {
        VideoPlaybackFeature.State(
            urlText: "",
            loadedVideoURL: nil,
            phase: .observing(.idle),
            observationID: nil
        )
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
