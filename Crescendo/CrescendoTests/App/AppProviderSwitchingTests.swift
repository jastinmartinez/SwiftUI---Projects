import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppProviderSwitchingTests {
    @Test
    func reselectingConnectedProviderIsNoOp() async {
        let events = LockIsolated<[String]>([])
        let state = makeState()
        let store = makeStore(
            state: state,
            pause: { events.withValue { $0.append("pause") } }
        )

        await store.send(.providerSelected(.appleMusic))

        #expect(store.state == state)
        #expect(events.value.isEmpty)
    }

    @Test
    func selectingConnectedProviderCancelsPendingSwitch() async {
        let pauseCount = LockIsolated(0)
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let state = makeState()
        let store = makeStore(
            state: state,
            pause: {
                pauseCount.withValue { $0 += 1 }
                pauseStartedContinuation.yield()
                try await Task.sleep(for: .seconds(60))
            }
        )

        await store.send(.providerSelected("future")) {
            $0.pendingProviderID = "future"
            $0.providerSwitchRequestID = UUID(0)
        }
        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()

        await store.send(.providerSelected(.appleMusic)) {
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
        }

        #expect(store.state == state)
        #expect(pauseCount.value == 1)
        await store.finish()
        pauseStartedContinuation.finish()
    }

    @Test
    func selectingPendingProviderDoesNotStartDuplicatePause() async {
        let pauseCount = LockIsolated(0)
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let access = makeAccess()
        let store = makeStore(
            pause: {
                pauseCount.withValue { $0 += 1 }
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            },
            currentAccess: { access }
        )

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
        )
        await store.receive(.providerConnection(.connect("future")))
        await store.receive(.providerConnection(.startConnection("future"))) {
            $0.providerConnection.connection = .connecting(
                providerID: "future",
                requestID: UUID(1)
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: "future",
                        providerChanged: true
                    )
                )
            )
        ) {
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
        }
        await store.receive(.resetProviderOwnedState("future")) {
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
        await store.receive(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(1),
                    providerID: "future",
                    access: access
                )
            )
        )
        await store.receive(
            .providerConnection(
                .accessResolved(
                    requestID: UUID(1),
                    providerID: "future",
                    access: access
                )
            )
        ) {
            $0.providerConnection.connection = .connected(
                providerID: "future",
                access: access
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(providerID: "future", access: access)
                    )
                )
            )
        ) {
            $0.search.playbackEligibility = .eligible
        }

        pauseStartedContinuation.finish()
    }

    @Test
    func switchingConnectedProviderPausesBeforeResolvingAccess() async {
        let events = LockIsolated<[String]>([])
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let access = makeAccess()
        let store = makeStore(
            pause: {
                events.withValue { $0.append("pause") }
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            },
            currentAccess: {
                events.withValue { $0.append("current-access") }
                return access
            }
        )

        await store.send(.providerSelected("future")) {
            $0.pendingProviderID = "future"
            $0.providerSwitchRequestID = UUID(0)
        }

        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()
        #expect(
            store.state.providerConnection.connection
                == .connected(
                    providerID: .appleMusic,
                    access: makeAccess()
                )
        )
        #expect(events.value == ["pause"])

        resumePauseContinuation.yield()
        resumePauseContinuation.finish()
        await store.receive(
            .providerSwitchPauseSucceeded(
                requestID: UUID(0),
                providerID: "future"
            )
        )
        await store.receive(.providerConnection(.connect("future")))
        await store.receive(.providerConnection(.startConnection("future"))) {
            $0.providerConnection.connection = .connecting(
                providerID: "future",
                requestID: UUID(1)
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: "future",
                        providerChanged: true
                    )
                )
            )
        ) {
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
        }
        await store.receive(.resetProviderOwnedState("future")) {
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
        await store.receive(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(1),
                    providerID: "future",
                    access: access
                )
            )
        )
        await store.receive(
            .providerConnection(
                .accessResolved(
                    requestID: UUID(1),
                    providerID: "future",
                    access: access
                )
            )
        ) {
            $0.providerConnection.connection = .connected(
                providerID: "future",
                access: access
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(providerID: "future", access: access)
                    )
                )
            )
        ) {
            $0.search.playbackEligibility = .eligible
        }

        #expect(events.value == ["pause", "current-access"])
        pauseStartedContinuation.finish()
    }

    @Test
    func providerSwitchPauseFailureKeepsConnectedState() async {
        let initialState = makeState()
        let store = makeStore(
            state: initialState,
            pause: { throw MusicProviderError.playbackFailed }
        )

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

        #expect(store.state == initialState)
    }

    @Test
    func staleAccessResponseCannotReplaceNewerConnection() async {
        let state = makeState(
            providerConnection: .connecting(
                providerID: "third",
                requestID: UUID(1)
            )
        )
        let store = makeStore(state: state)
        let access = makeAccess()

        await store.send(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(0),
                    providerID: "future",
                    access: access
                )
            )
        )
        await store.send(
            .providerConnection(
                .requestedAccessResponse(
                    requestID: UUID(0),
                    providerID: "third",
                    access: access
                )
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
        let access = makeAccess()
        let store = makeStore(
            pause: {
                let call = pauseCount.withValue { count in
                    count += 1
                    return count
                }
                events.withValue { $0.append("pause-\(call)") }
                if call == 1 {
                    firstPauseStartedContinuation.yield()
                    try await Task.sleep(for: .seconds(60))
                }
            },
            currentAccess: { access }
        )

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
        )
        await store.receive(.providerConnection(.connect("third")))
        await store.receive(.providerConnection(.startConnection("third"))) {
            $0.providerConnection.connection = .connecting(
                providerID: "third",
                requestID: UUID(2)
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: "third",
                        providerChanged: true
                    )
                )
            )
        ) {
            $0.pendingProviderID = nil
            $0.providerSwitchRequestID = nil
        }
        await store.receive(.resetProviderOwnedState("third")) {
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
        await store.receive(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(2),
                    providerID: "third",
                    access: access
                )
            )
        )
        await store.receive(
            .providerConnection(
                .accessResolved(
                    requestID: UUID(2),
                    providerID: "third",
                    access: access
                )
            )
        ) {
            $0.providerConnection.connection = .connected(
                providerID: "third",
                access: access
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(providerID: "third", access: access)
                    )
                )
            )
        ) {
            $0.search.playbackEligibility = .eligible
        }

        #expect(events.value == ["pause-1", "pause-2"])
        await store.finish()
        firstPauseStartedContinuation.finish()
    }

    @Test
    func providerSelectionIsIgnoredDuringPlaybackTransition() async {
        let events = LockIsolated<[String]>([])
        let state = makeState(playbackTransition: .startingMusic(makeSong().id))
        let store = makeStore(
            state: state,
            pause: { events.withValue { $0.append("pause") } }
        )

        await store.send(.providerSelected("future"))

        #expect(store.state == state)
        #expect(events.value.isEmpty)
    }

    @Test
    func musicStartIsIgnoredDuringProviderSwitch() async {
        let events = LockIsolated<[String]>([])
        let song = makeSong()
        let state = makeState(
            pendingProviderID: "future",
            providerSwitchRequestID: UUID(0)
        )
        let store = makeStore(
            state: state,
            play: { _ in events.withValue { $0.append("play-music") } }
        )

        await store.send(.musicPlayback(.delegate(.playRequested(song.id))))

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

    private func makeStore(
        state: AppFeature.State? = nil,
        pause: @escaping @Sendable () async throws -> Void = {},
        play: @escaping @Sendable (MusicItemID) async throws -> Void = { _ in },
        currentAccess: @escaping @Sendable () async -> MusicProviderAccess = {
            MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .eligible
            )
        }
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state ?? makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.pause = pause
            $0.musicProvider.play = play
            $0.musicProvider.currentAccess = currentAccess
        }
    }

    private func makeState(
        providerConnection: ProviderConnection? = nil,
        pendingProviderID: ProviderID? = nil,
        providerSwitchRequestID: UUID? = nil,
        playbackTransition: PlaybackTransition? = nil
    ) -> AppFeature.State {
        AppFeature.State(
            providerConnection: ProviderConnectionFeature.State(
                providers: [
                    .appleMusic,
                    makeProvider(
                        id: "future",
                        musicCapabilities: futureCapabilities
                    ),
                    makeProvider(
                        id: "third",
                        musicCapabilities: .allEnabled
                    ),
                ],
                connection: providerConnection
                    ?? .connected(
                        providerID: .appleMusic,
                        access: makeAccess()
                    )
            ),
            search: makeSearchState(),
            musicPlayback: makeMusicPlaybackState(),
            isPlayerPresented: true,
            pendingProviderID: pendingProviderID,
            providerSwitchRequestID: providerSwitchRequestID,
            playbackTransition: playbackTransition
        )
    }

    private func makeProvider(
        id: ProviderID,
        musicCapabilities: MusicProviderCapabilities
    ) -> ProviderDescriptor {
        ProviderDescriptor(
            id: id,
            name: "Future",
            musicCapabilities: musicCapabilities
        )
    }

    private func makeAccess() -> MusicProviderAccess {
        MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
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

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: .appleMusic, nativeID: "selected"),
            title: "Selected song",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }

}
