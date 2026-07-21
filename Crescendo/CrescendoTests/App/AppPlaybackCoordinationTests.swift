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
        let requestID = UUID(0)
        let store = makeStore(song: song, calls: calls)

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(
            .playbackCommand(.execute(command, requestID: requestID))
        )
        await store.receive(
            .playbackCommand(
                .response(requestID: requestID, result: .success(command))
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(requestID: requestID, result: .success(command))
                )
            )
        ) {
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
        let requestID = UUID(0)
        let store = makeStore(
            song: song,
            phase: .observing(snapshot),
            calls: calls
        )

        await store.send(.musicPlayback(.delegate(.resumeRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(snapshot)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(
            .playbackCommand(.execute(command, requestID: requestID))
        )
        await store.receive(
            .playbackCommand(
                .response(requestID: requestID, result: .success(command))
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(requestID: requestID, result: .success(command))
                )
            )
        ) {
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
                $0.playbackControl.play = { _ in
                    throw MusicProviderError.network
                }
                $0.playbackControl.resume = {
                    throw MusicProviderError.network
                }
            }
        )
        let requestID = UUID(0)
        let delegate: MusicPlaybackFeature.Delegate =
            switch command {
            case .play(let itemID):
                .playRequested(itemID)
            case .resume(let itemID):
                .resumeRequested(itemID)
            }

        await store.send(.musicPlayback(.delegate(delegate))) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(initialSnapshot)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(
            .playbackCommand(.execute(command, requestID: requestID))
        )
        await store.receive(
            .playbackCommand(
                .response(requestID: requestID, result: .failure(.network))
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(requestID: requestID, result: .failure(.network))
                )
            )
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

    @Test
    func activeCommandIsReplacedByLatestPlaybackRequest() async {
        let song = makeSong()
        let firstCommand = PlaybackCommandFeature.Command.play(song.id)
        let latestItemID = MusicItemID(providerID: "fake", nativeID: "2")
        let state = makeState(
            song: song,
            phase: .loading(.idle),
            playbackCommand: PlaybackCommandFeature.State(
                command: firstCommand,
                requestID: UUID(99)
            )
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackControl.play = { _ in }
        }

        await store.send(
            .musicPlayback(.delegate(.playRequested(latestItemID)))
        )
        await store.receive(
            .playbackCommand(
                .replace(.play(latestItemID), requestID: UUID(0))
            )
        )
        await store.receive(\.musicPlayback.playbackCommandAccepted)
        await store.receive(
            .playbackCommand(
                .execute(.play(latestItemID), requestID: UUID(0))
            )
        ) {
            $0.playbackCommand?.command = .play(latestItemID)
            $0.playbackCommand?.requestID = UUID(0)
        }
        await store.receive(
            .playbackCommand(
                .response(
                    requestID: UUID(0),
                    result: .success(.play(latestItemID))
                )
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(
                        requestID: UUID(0),
                        result: .success(.play(latestItemID))
                    )
                )
            )
        ) {
            $0.playbackCommand = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(.idle)
        }
    }

    @Test
    func staleDelegatesDoNotClearACommandWithDifferentRequestID() async {
        let song = makeSong()
        let activeCommand = PlaybackCommandFeature.Command.play(song.id)
        let activeRequestID = UUID(1)
        let staleRequestID = UUID(0)
        let state = makeState(
            song: song,
            phase: .loading(.idle),
            playbackCommand: PlaybackCommandFeature.State(
                command: activeCommand,
                requestID: activeRequestID
            )
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(
            .playbackCommand(
                .delegate(
                    .completed(
                        requestID: staleRequestID,
                        result: .success(activeCommand)
                    )
                )
            )
        )
        await store.send(
            .playbackCommand(
                .delegate(
                    .completed(
                        requestID: staleRequestID,
                        result: .failure(.network)
                    )
                )
            )
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
        let requestID = UUID(0)
        let store = makeStore(song: song) {
            $0.playbackControl.play = { _ in
                playStartedContinuation.yield()
                for await _ in finishPlay { break }
            }
        }

        await store.send(.musicPlayback(.delegate(.playRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(.idle)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(
            .playbackCommand(.execute(command, requestID: requestID))
        )

        var playStartedIterator = playStarted.makeAsyncIterator()
        _ = await playStartedIterator.next()
        await store.send(.musicPlayback(.snapshotReceived(latestSnapshot))) {
            $0.musicPlayback.phase = .loading(latestSnapshot)
        }

        finishPlayContinuation.yield()
        finishPlayContinuation.finish()
        await store.receive(
            .playbackCommand(
                .response(requestID: requestID, result: .success(command))
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(requestID: requestID, result: .success(command))
                )
            )
        ) {
            $0.playbackCommand = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(latestSnapshot)
        }
        playStartedContinuation.finish()
    }

    @Test
    func tappingDifferentTrackWhilePlayingSelectsAndPlaysTappedTrack() async {
        let currentSong = makeSong(nativeID: "current")
        let nextSong = makeSong(nativeID: "next")
        let playedItemIDs = LockIsolated<[MusicItemID]>([])
        let state = makeState(
            song: currentSong,
            phase: .observing(
                makeSnapshot(song: currentSong, status: .playing)
            )
        )
        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackControl.play = { itemID in
                playedItemIDs.withValue { $0.append(itemID) }
            }
        }

        await store.send(
            .search(
                .delegate(
                    .songTapped(nextSong, loadedResults: [nextSong])
                )
            )
        )
        await store.receive(
            .musicPlayback(
                .songTapped(nextSong, playbackEligibility: .eligible)
            )
        )
        await store.receive(.musicPlayback(.timeline(.reset)))
        await store.receive(
            .musicPlayback(
                .applySongTap(nextSong, playbackEligibility: .eligible)
            )
        ) {
            $0.musicPlayback.selectedSong = nextSong
            $0.musicPlayback.playbackEligibility = .eligible
        }
        await store.receive(.musicPlayback(.requestPlayback))
        await store.receive(
            .musicPlayback(.delegate(.playRequested(nextSong.id)))
        ) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: .play(nextSong.id),
                requestID: UUID(0)
            )
        }
        await store.receive(\.musicPlayback.playbackCommandAccepted) {
            $0.musicPlayback.phase = .loading(
                makeSnapshot(song: currentSong, status: .playing)
            )
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(
            .playbackCommand(
                .execute(.play(nextSong.id), requestID: UUID(0))
            )
        )
        await store.receive(
            .playbackCommand(
                .response(
                    requestID: UUID(0),
                    result: .success(.play(nextSong.id))
                )
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(
                        requestID: UUID(0),
                        result: .success(.play(nextSong.id))
                    )
                )
            )
        ) {
            $0.playbackCommand = nil
        }
        await store.receive(\.musicPlayback.transportFinished) {
            $0.musicPlayback.phase = .observing(
                makeSnapshot(song: currentSong, status: .playing)
            )
        }

        #expect(store.state.musicPlayback.selectedSong == nextSong)
        #expect(playedItemIDs.value == [nextSong.id])
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
            $0.uuid = .incrementing
            $0.playbackControl.play = { itemID in
                calls?.withValue { $0.playedItemIDs.append(itemID) }
            }
            $0.playbackControl.resume = {
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
                status: .idle,
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
