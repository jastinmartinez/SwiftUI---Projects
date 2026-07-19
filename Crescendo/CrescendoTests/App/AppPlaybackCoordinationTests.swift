import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func playRequestCallsOnlyPlayAndClearsMatchingCommandOnSuccess() async {
        let song = makeSong()
        let calls = LockIsolated(TransportCalls())
        let command = PlaybackCommandFeature.Command.play(song.id)
        let store = makeStore(song: song, calls: calls)

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(command: command)
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(.playbackCommand(.commandSucceeded))
        await store.receive(.playbackCommand(.delegate(.succeeded(command)))) {
            $0.playbackCommand = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(.idle)
        }

        #expect(calls.value.playedItemIDs == [song.id])
        #expect(calls.value.resumeCallCount == 0)
    }

    @Test
    func resumeRequestCallsOnlyResumeAndClearsMatchingCommandOnSuccess() async {
        let song = makeSong()
        let snapshot = makeSnapshot(song: song, status: .paused)
        let calls = LockIsolated(TransportCalls())
        let command = PlaybackCommandFeature.Command.resume(song.id)
        let store = makeStore(
            song: song,
            phase: .observing(snapshot),
            calls: calls
        )

        await store.send(.musicPlayback(.delegate(.resumeRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(command: command)
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(snapshot)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(.playbackCommand(.commandSucceeded))
        await store.receive(.playbackCommand(.delegate(.succeeded(command)))) {
            $0.playbackCommand = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(snapshot)
        }

        #expect(calls.value.playedItemIDs.isEmpty)
        #expect(calls.value.resumeCallCount == 1)
    }

    @Test(arguments: [
        PlaybackCommandFeature.Command.play(
            MusicItemID(providerID: "fake", nativeID: "1")
        ),
        .resume(MusicItemID(providerID: "fake", nativeID: "1")),
    ])
    func failedCommandClearsMatchingChildAndReportsProviderError(
        command: PlaybackCommandFeature.Command
    ) async {
        let song = makeSong()
        let initialSnapshot =
            command == .resume(song.id)
            ? makeSnapshot(song: song, status: .paused)
            : .idle
        let store = makeStore(
            song: song,
            phase: .observing(initialSnapshot),
            configureDependencies: {
                $0.musicProvider.play = { _ in
                    throw MusicProviderError.network
                }
                $0.musicProvider.resume = {
                    throw MusicProviderError.network
                }
            }
        )
        let delegate: MusicPlaybackFeature.Delegate =
            switch command {
            case .play(let itemID):
                .playRequested(itemID)
            case .resume(let itemID):
                .resumeRequested(itemID)
            }

        await store.send(.musicPlayback(.delegate(delegate))) {
            $0.playbackCommand = PlaybackCommandFeature.State(command: command)
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(initialSnapshot)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(.playbackCommand(.commandFailed(.network)))
        await store.receive(
            .playbackCommand(.delegate(.failed(command, .network)))
        ) {
            $0.playbackCommand = nil
        }
        await store.receive(\.musicPlayback.transportFailed) {
            $0.musicPlayback.phase = .failed(
                .network,
                lastSnapshot: initialSnapshot
            )
        }
    }

    @Test(arguments: [
        PlaybackCommandFeature.Command.play(
            MusicItemID(providerID: "fake", nativeID: "1")
        ),
        .resume(MusicItemID(providerID: "fake", nativeID: "1")),
    ])
    func activeCommandRejectsDuplicatePlayAndResumeRequests(
        command: PlaybackCommandFeature.Command
    ) async {
        let song = makeSong()
        let otherItemID = MusicItemID(providerID: "fake", nativeID: "2")
        let state = makeState(
            song: song,
            phase: .loading(.idle),
            playbackCommand: PlaybackCommandFeature.State(command: command)
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(
            .musicPlayback(.delegate(.playRequested(otherItemID)))
        )
        await store.send(
            .musicPlayback(.delegate(.resumeRequested(otherItemID)))
        )

        #expect(store.state == state)
    }

    @Test
    func staleDelegatesDoNotClearACommandWithDifferentIntent() async {
        let song = makeSong()
        let activeCommand = PlaybackCommandFeature.Command.play(song.id)
        let staleCommand = PlaybackCommandFeature.Command.resume(song.id)
        let state = makeState(
            song: song,
            phase: .loading(.idle),
            playbackCommand: PlaybackCommandFeature.State(
                command: activeCommand
            )
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(
            .playbackCommand(.delegate(.succeeded(staleCommand)))
        )
        await store.send(
            .playbackCommand(.delegate(.failed(staleCommand, .network)))
        )

        #expect(store.state == state)
    }

    @Test
    func playbackCommandPreservesLatestSnapshotWhileInFlight() async {
        let song = makeSong()
        let latestSnapshot = makeSnapshot(song: song, status: .paused)
        let (playStarted, playStartedContinuation) = AsyncStream<Void>.makeStream()
        let (finishPlay, finishPlayContinuation) = AsyncStream<Void>.makeStream()
        let command = PlaybackCommandFeature.Command.play(song.id)
        let store = makeStore(song: song) {
            $0.musicProvider.play = { _ in
                playStartedContinuation.yield()
                for await _ in finishPlay { break }
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(command: command)
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }
        await store.receive(.playbackCommand(.start))

        var playStartedIterator = playStarted.makeAsyncIterator()
        _ = await playStartedIterator.next()
        await store.send(.musicPlayback(.snapshotReceived(latestSnapshot))) {
            $0.musicPlayback.phase = .loading(latestSnapshot)
        }

        finishPlayContinuation.yield()
        finishPlayContinuation.finish()
        await store.receive(.playbackCommand(.commandSucceeded))
        await store.receive(.playbackCommand(.delegate(.succeeded(command)))) {
            $0.playbackCommand = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(latestSnapshot)
        }
        playStartedContinuation.finish()
    }

    // MARK: - Helpers

    private struct TransportCalls: Equatable {
        var playedItemIDs: [MusicItemID] = []
        var resumeCallCount = 0
    }

    private func makeStore(
        song: SongSummary,
        phase: MusicPlaybackFeature.Phase = .observing(.idle),
        calls: LockIsolated<TransportCalls>? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: makeState(song: song, phase: phase)) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.play = { itemID in
                calls?.withValue { $0.playedItemIDs.append(itemID) }
            }
            $0.musicProvider.resume = {
                calls?.withValue { $0.resumeCallCount += 1 }
            }
            configureDependencies(&$0)
        }
    }

    private func makeState(
        song: SongSummary,
        phase: MusicPlaybackFeature.Phase,
        playbackCommand: PlaybackCommandFeature.State? = nil
    ) -> AppFeature.State {
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
                phase: phase,
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: MusicPlaybackTimelineFeature.State(
                    interaction: .idle
                )
            ),
            isPlayerPresented: false,
            providerSwitch: nil,
            playbackCommand: playbackCommand
        )
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
