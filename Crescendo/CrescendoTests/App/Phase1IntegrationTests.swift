import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct Phase1IntegrationTests {
    @Test
    func reselectingActiveProviderWithoutPendingSwitchIsNoOp() async {
        let events = LockIsolated<[String]>([])
        let state = makeState()
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.pause = {
                events.withValue { $0.append("pause") }
            }
        }

        await store.send(.providerSelected("apple-music"))

        #expect(store.state == state)
        #expect(events.value.isEmpty)
    }

    @Test
    func selectingActiveProviderCancelsPendingSwitchWithoutResettingState() async {
        let events = LockIsolated<[String]>([])
        let pauseCount = LockIsolated(0)
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let state = makeState()
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.pause = {
                let call = pauseCount.withValue { count in
                    count += 1
                    return count
                }
                events.withValue { $0.append("pause-\(call)") }
                if call == 1 {
                    pauseStartedContinuation.yield()
                    try await Task.sleep(for: .seconds(60))
                }
            }
        }

        await store.send(.providerSelected("future")) {
            $0.pendingProviderID = "future"
            $0.providerSwitchRequestID = UUID(0)
        }
        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()

        await store.send(.providerSelected("apple-music")) {
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
        }

        #expect(store.state == state)
        #expect(events.value == ["pause-1"])
        await store.finish()
        pauseStartedContinuation.finish()
    }

    @Test
    func selectingPendingProviderAgainDoesNotStartDuplicatePause() async {
        let pauseCount = LockIsolated(0)
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.pause = {
                pauseCount.withValue { $0 += 1 }
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            }
        }

        await store.send(.providerSelected("future")) {
            $0.pendingProviderID = "future"
            $0.providerSwitchRequestID = UUID(0)
        }
        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()

        await store.send(.providerSelected("future"))
        #expect(pauseCount.value == 1)

        resumePauseContinuation.yield()
        resumePauseContinuation.finish()
        await store.receive(
            .providerSwitchPauseSucceeded(
                requestID: UUID(0),
                providerID: "future"
            )
        ) {
            $0.activeProviderID = "future"
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
            $0.search = SearchFeature.State(
                query: "",
                phase: .idle,
                playbackEligibility: .unknown
            )
            $0.musicPlayback = MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: futureCapabilities
            )
            $0.isPlayerPresented = false
        }

        await store.finish()
        pauseStartedContinuation.finish()
    }

    @Test
    func providerSwitchPausesBeforeResettingProviderOwnedState() async {
        let events = LockIsolated<[String]>([])
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.pause = {
                events.withValue { $0.append("pause") }
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            }
        }

        await store.send(.providerSelected("future")) {
            $0.pendingProviderID = "future"
            $0.providerSwitchRequestID = UUID(0)
        }

        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()
        #expect(store.state.activeProviderID == "apple-music")
        #expect(store.state.search == makeSearchState())
        #expect(store.state.musicPlayback == makeMusicPlaybackState())
        #expect(store.state.isPlayerPresented)
        #expect(events.value == ["pause"])

        resumePauseContinuation.yield()
        resumePauseContinuation.finish()
        await store.receive(
            .providerSwitchPauseSucceeded(
                requestID: UUID(0),
                providerID: "future"
            )
        ) {
            $0.activeProviderID = "future"
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
            $0.search = SearchFeature.State(
                query: "",
                phase: .idle,
                playbackEligibility: .unknown
            )
            $0.musicPlayback = MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: futureCapabilities
            )
            $0.isPlayerPresented = false
        }

        #expect(events.value == ["pause"])
        await store.finish()
        pauseStartedContinuation.finish()
    }

    @Test
    func providerSwitchFailureKeepsActiveProviderState() async {
        let initialState = makeState()
        let store = TestStore(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.pause = {
                throw MusicProviderError.playbackFailed
            }
        }

        await store.send(.providerSelected("future")) {
            $0.pendingProviderID = "future"
            $0.providerSwitchRequestID = UUID(0)
        }
        await store.receive(
            .providerSwitchPauseFailed(
                requestID: UUID(0),
                providerID: "future"
            )
        ) {
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
        }

        #expect(store.state.activeProviderID == initialState.activeProviderID)
        #expect(store.state.search == initialState.search)
        #expect(store.state.musicPlayback == initialState.musicPlayback)
        #expect(store.state.isPlayerPresented == initialState.isPlayerPresented)
    }

    @Test
    func staleProviderSwitchSuccessAndFailureAreIgnored() async {
        let activeRequestID = UUID(1)
        let state = makeState(
            pendingProviderID: "future",
            providerSwitchRequestID: activeRequestID
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(
            .providerSwitchPauseSucceeded(
                requestID: UUID(0),
                providerID: "future"
            )
        )
        await store.send(
            .providerSwitchPauseSucceeded(
                requestID: activeRequestID,
                providerID: "third"
            )
        )
        await store.send(
            .providerSwitchPauseFailed(
                requestID: UUID(0),
                providerID: "future"
            )
        )

        #expect(store.state == state)
    }

    @Test
    func latestProviderSelectionCancelsEarlierPauseRequest() async {
        let events = LockIsolated<[String]>([])
        let pauseCount = LockIsolated(0)
        let (firstPauseStarted, firstPauseStartedContinuation) =
            AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.pause = {
                let call = pauseCount.withValue { count in
                    count += 1
                    return count
                }
                events.withValue { $0.append("pause-\(call)") }
                if call == 1 {
                    firstPauseStartedContinuation.yield()
                    try await Task.sleep(for: .seconds(60))
                }
            }
        }

        await store.send(.providerSelected("future")) {
            $0.pendingProviderID = "future"
            $0.providerSwitchRequestID = UUID(0)
        }
        var firstPauseStartedIterator = firstPauseStarted.makeAsyncIterator()
        _ = await firstPauseStartedIterator.next()

        await store.send(.providerSelected("third")) {
            $0.pendingProviderID = "third"
            $0.providerSwitchRequestID = UUID(1)
        }
        await store.receive(
            .providerSwitchPauseSucceeded(
                requestID: UUID(1),
                providerID: "third"
            )
        ) {
            $0.activeProviderID = "third"
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
            $0.search = SearchFeature.State(
                query: "",
                phase: .idle,
                playbackEligibility: .unknown
            )
            $0.musicPlayback = MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: .allEnabled
            )
            $0.isPlayerPresented = false
        }

        #expect(events.value == ["pause-1", "pause-2"])
        await store.finish()
        firstPauseStartedContinuation.finish()
    }

    @Test
    func providerSwitchIsIgnoredDuringPlaybackTransition() async {
        let events = LockIsolated<[String]>([])
        let state = makeState(playbackTransition: .openingVideo)
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.pause = {
                events.withValue { $0.append("pause") }
            }
        }

        await store.send(.providerSelected("future"))

        #expect(store.state == state)
        #expect(events.value.isEmpty)
    }

    @Test
    func providerSwitchIsIgnoredDuringVideoClose() async {
        let events = LockIsolated<[String]>([])
        let state = makeState(videoCloseRequestID: UUID(0))
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.pause = {
                events.withValue { $0.append("pause") }
            }
        }

        await store.send(.providerSelected("future"))

        #expect(store.state == state)
        #expect(events.value.isEmpty)
    }

    @Test
    func musicStartAndVideoOpenAreIgnoredDuringProviderSwitch() async {
        let events = LockIsolated<[String]>([])
        let song = makeSong()
        let state = makeState(
            pendingProviderID: "future",
            providerSwitchRequestID: UUID(0)
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.videoPlayback.pause = {
                events.withValue { $0.append("pause-video") }
            }
            $0.musicProvider.pause = {
                events.withValue { $0.append("pause-music") }
            }
            $0.musicProvider.play = { _ in
                events.withValue { $0.append("play-music") }
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id))))
        await store.send(.openVideoButtonTapped)

        #expect(store.state == state)
        #expect(events.value.isEmpty)
    }

    @Test
    func videoCloseIsIgnoredDuringProviderSwitch() async {
        let events = LockIsolated<[String]>([])
        let state = makeState(
            video: makeVideoState(),
            pendingProviderID: "future",
            providerSwitchRequestID: UUID(0)
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.videoPlayback.pause = {
                events.withValue { $0.append("pause-video") }
            }
            $0.videoPlayback.clear = {
                events.withValue { $0.append("clear-video") }
            }
        }

        await store.send(.closeVideoRequested)

        #expect(store.state == state)
        #expect(events.value.isEmpty)
    }

    // MARK: - Helpers

    private var futureCapabilities: MusicProviderCapabilities {
        MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: false,
            supportsQueueReplacement: true
        )
    }

    private func makeState(
        video: VideoPlaybackFeature.State? = nil,
        videoCloseRequestID: UUID? = nil,
        pendingProviderID: MusicProviderID? = nil,
        providerSwitchRequestID: UUID? = nil,
        playbackTransition: PlaybackTransition? = nil
    ) -> AppFeature.State {
        AppFeature.State(
            registeredProviders: [
                .appleMusic,
                makeProvider(id: "future", capabilities: futureCapabilities),
                makeProvider(id: "third", capabilities: .allEnabled),
            ],
            activeProviderID: "apple-music",
            search: makeSearchState(),
            musicPlayback: makeMusicPlaybackState(),
            isPlayerPresented: true,
            video: video,
            videoCloseRequestID: videoCloseRequestID,
            pendingProviderID: pendingProviderID,
            providerSwitchRequestID: providerSwitchRequestID,
            playbackTransition: playbackTransition
        )
    }

    private func makeProvider(
        id: MusicProviderID,
        capabilities: MusicProviderCapabilities
    ) -> MusicProviderDescriptor {
        MusicProviderDescriptor(id: id, capabilities: capabilities)
    }

    private func makeSearchState() -> SearchFeature.State {
        SearchFeature.State(
            query: "Selected song",
            phase: .loaded([makeSong()]),
            playbackEligibility: .eligible
        )
    }

    private func makeMusicPlaybackState() -> MusicPlaybackFeature.State {
        let song = makeSong()
        return MusicPlaybackFeature.State(
            selectedSong: song,
            phase: .observing(
                MusicPlaybackSnapshot(
                    currentItem: song,
                    status: .playing,
                    currentTime: 42
                )
            ),
            playbackEligibility: .eligible,
            capabilities: .allEnabled
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
            id: .init(providerID: "apple-music", nativeID: "selected"),
            title: "Selected song",
            artistName: "Artist",
            artworkURL: nil
        )
    }
}
