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
        let command = makePlayCommand(song.id)
        let requestID = UUID(0)
        let store = makeStore(song: song, calls: calls)

        await store.send(.playback(.delegate(.playRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        }
        await store.receive(\.playback.playbackCommandAccepted) {
            $0.playback.phase = .loading(.idle)
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
        await store.receive(\.playback.transportFinished) {
            $0.playback.phase = .observing(.idle)
        }

        #expect(calls.value.startingItemIDs == [song.id])
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

        await store.send(.playback(.delegate(.resumeRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        }
        await store.receive(\.playback.playbackCommandAccepted) {
            $0.playback.phase = .loading(snapshot)
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
        await store.receive(\.playback.transportFinished) {
            $0.playback.phase = .observing(snapshot)
        }

        #expect(calls.value.startingItemIDs.isEmpty)
        #expect(calls.value.resumeCallCount == 1)
    }

    @Test(arguments: [
        PlaybackCommandFeature.Command.play(
            itemIDs: [MusicItemID(providerID: "fake", nativeID: "1")],
            startingItemID: MusicItemID(providerID: "fake", nativeID: "1")
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
                $0.playbackControl.playQueue = { _, _ in
                    throw MusicProviderError.network
                }
                $0.playbackControl.resume = {
                    throw MusicProviderError.network
                }
            }
        )
        let requestID = UUID(0)
        let delegate: PlaybackFeature.Delegate =
            switch command {
            case .play(_, let startingItemID):
                .playRequested(startingItemID)
            case .resume(let itemID):
                .resumeRequested(itemID)
            }

        await store.send(.playback(.delegate(delegate))) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        }
        await store.receive(\.playback.playbackCommandAccepted) {
            $0.playback.phase = .loading(initialSnapshot)
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
        await store.receive(\.playback.transportFailed) {
            $0.playback.phase = .failed(
                .network,
                lastSnapshot: initialSnapshot
            )
        }
    }

    @Test
    func activeCommandIsReplacedByLatestPlaybackRequest() async {
        let song = makeSong()
        let firstCommand = makePlayCommand(song.id)
        let latestItemID = MusicItemID(providerID: "fake", nativeID: "2")
        let latestCommand = makePlayCommand(latestItemID)
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
            $0.playbackControl.playQueue = { _, _ in }
        }

        await store.send(
            .playback(.delegate(.playRequested(latestItemID)))
        )
        await store.receive(
            .playbackCommand(
                .replace(latestCommand, requestID: UUID(0))
            )
        )
        await store.receive(\.playback.playbackCommandAccepted)
        await store.receive(
            .playbackCommand(
                .execute(latestCommand, requestID: UUID(0))
            )
        ) {
            $0.playbackCommand?.command = latestCommand
            $0.playbackCommand?.requestID = UUID(0)
        }
        await store.receive(
            .playbackCommand(
                .response(
                    requestID: UUID(0),
                    result: .success(latestCommand)
                )
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(
                        requestID: UUID(0),
                        result: .success(latestCommand)
                    )
                )
            )
        ) {
            $0.playbackCommand = nil
        }
        await store.receive(\.playback.transportFinished) {
            $0.playback.phase = .observing(.idle)
        }
    }

    @Test
    func staleDelegatesDoNotClearACommandWithDifferentRequestID() async {
        let song = makeSong()
        let activeCommand = makePlayCommand(song.id)
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
        let command = makePlayCommand(song.id)
        let requestID = UUID(0)
        let store = makeStore(song: song) {
            $0.playbackControl.playQueue = { _, _ in
                playStartedContinuation.yield()
                for await _ in finishPlay { break }
            }
        }

        await store.send(.playback(.delegate(.playRequested(song.id)))) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        }
        await store.receive(\.playback.playbackCommandAccepted) {
            $0.playback.phase = .loading(.idle)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(
            .playbackCommand(.execute(command, requestID: requestID))
        )

        var playStartedIterator = playStarted.makeAsyncIterator()
        _ = await playStartedIterator.next()
        await store.send(.playback(.snapshotReceived(latestSnapshot))) {
            $0.playback.phase = .loading(latestSnapshot)
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
        await store.receive(\.playback.transportFinished) {
            $0.playback.phase = .observing(latestSnapshot)
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
            $0.playbackControl.playQueue = { _, startingItemID in
                playedItemIDs.withValue { $0.append(startingItemID) }
            }
        }
        let command = makePlayCommand(nextSong.id)

        await store.send(
            .search(
                .delegate(
                    .songTapped(nextSong, loadedResults: [nextSong])
                )
            )
        )
        await store.receive(
            .playback(
                .songTapped(nextSong, playbackEligibility: .eligible)
            )
        )
        await store.receive(.playback(.timeline(.reset)))
        await store.receive(
            .playback(
                .applySongTap(nextSong, playbackEligibility: .eligible)
            )
        ) {
            $0.playback.selectedSong = nextSong
            $0.playback.playbackEligibility = .eligible
        }
        await store.receive(.playback(.requestPlayback))
        await store.receive(
            .playback(.delegate(.playRequested(nextSong.id)))
        ) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: command,
                requestID: UUID(0)
            )
        }
        await store.receive(\.playback.playbackCommandAccepted) {
            $0.playback.phase = .loading(
                makeSnapshot(song: currentSong, status: .playing)
            )
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(
            .playbackCommand(
                .execute(command, requestID: UUID(0))
            )
        )
        await store.receive(
            .playbackCommand(
                .response(
                    requestID: UUID(0),
                    result: .success(command)
                )
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(
                        requestID: UUID(0),
                        result: .success(command)
                    )
                )
            )
        ) {
            $0.playbackCommand = nil
        }
        await store.receive(\.playback.transportFinished) {
            $0.playback.phase = .observing(
                makeSnapshot(song: currentSong, status: .playing)
            )
        }

        #expect(store.state.playback.selectedSong == nextSong)
        #expect(playedItemIDs.value == [nextSong.id])
    }

    // MARK: - Helpers

    private struct TransportCalls: Equatable {
        var startingItemIDs: [MusicItemID] = []
        var resumeCallCount = 0
    }

    private func makeStore(
        song: SongSummary,
        phase: PlaybackFeature.Phase = .observing(.idle),
        calls: LockIsolated<TransportCalls>? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: makeState(song: song, phase: phase)) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackControl.playQueue = { _, startingItemID in
                calls?.withValue { $0.startingItemIDs.append(startingItemID) }
            }
            $0.playbackControl.resume = {
                calls?.withValue { $0.resumeCallCount += 1 }
            }
            configureDependencies(&$0)
        }
    }

    private func makePlayCommand(
        _ startingItemID: MusicItemID
    ) -> PlaybackCommandFeature.Command {
        .play(
            itemIDs: [startingItemID],
            startingItemID: startingItemID
        )
    }

    private func makeState(
        song: SongSummary,
        phase: PlaybackFeature.Phase,
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
            playback: PlaybackFeature.State(
                selectedSong: song,
                queue: PlaybackQueueFeature.State(
                    songs: [],
                    currentItemID: nil
                ),
                phase: phase,
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: PlaybackTimelineFeature.State(
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
        status: PlaybackStatus
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            currentItemID: song.id,
            status: status,
            currentTime: 42,
            playbackRate: .normal,
            repeatMode: .off,
            shuffleMode: .off
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
