import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackCommandFeatureTests {
    @Test
    func playCommandCallsPlayOnlyAndDelegatesItsCommand() async {
        let itemID = makeItemID()
        let playedItemIDs = LockIsolated<[MusicItemID]>([])
        let resumeCallCount = LockIsolated(0)
        let command = PlaybackCommandFeature.Command.play(itemID)
        let requestID = UUID(0)
        let store = makeStore(command: command, requestID: requestID) {
            $0.musicProvider.play = { receivedItemID in
                playedItemIDs.withValue { $0.append(receivedItemID) }
            }
            $0.musicProvider.resume = {
                resumeCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.start)
        await store.receive(.execute(command, requestID: requestID))
        await store.receive(
            .response(requestID: requestID, result: .success(command))
        )
        await store.receive(
            .delegate(.completed(requestID: requestID, result: .success(command)))
        )

        #expect(playedItemIDs.value == [itemID])
        #expect(resumeCallCount.value == 0)
    }

    @Test
    func resumeCommandCallsResumeOnlyAndDelegatesItsCommand() async {
        let itemID = makeItemID()
        let playedItemIDs = LockIsolated<[MusicItemID]>([])
        let resumeCallCount = LockIsolated(0)
        let command = PlaybackCommandFeature.Command.resume(itemID)
        let requestID = UUID(0)
        let store = makeStore(command: command, requestID: requestID) {
            $0.musicProvider.play = { receivedItemID in
                playedItemIDs.withValue { $0.append(receivedItemID) }
            }
            $0.musicProvider.resume = {
                resumeCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.start)
        await store.receive(.execute(command, requestID: requestID))
        await store.receive(
            .response(requestID: requestID, result: .success(command))
        )
        await store.receive(
            .delegate(.completed(requestID: requestID, result: .success(command)))
        )

        #expect(playedItemIDs.value.isEmpty)
        #expect(resumeCallCount.value == 1)
    }

    @Test(arguments: [
        PlaybackCommandFeature.Command.play(
            MusicItemID(providerID: "fake", nativeID: "song-1")
        ),
        .resume(
            MusicItemID(providerID: "fake", nativeID: "song-1")
        ),
    ])
    func providerFailurePreservesTypedErrorAndCommand(
        command: PlaybackCommandFeature.Command
    ) async {
        let requestID = UUID(0)
        let store = makeStore(command: command, requestID: requestID) {
            $0.musicProvider.play = { _ in
                throw MusicProviderError.network
            }
            $0.musicProvider.resume = {
                throw MusicProviderError.network
            }
        }

        await store.send(.start)
        await store.receive(.execute(command, requestID: requestID))
        await store.receive(
            .response(requestID: requestID, result: .failure(.network))
        )
        await store.receive(
            .delegate(.completed(requestID: requestID, result: .failure(.network)))
        )
    }

    @Test(arguments: [
        PlaybackCommandFeature.Command.play(
            MusicItemID(providerID: "fake", nativeID: "song-1")
        ),
        .resume(
            MusicItemID(providerID: "fake", nativeID: "song-1")
        ),
    ])
    func unknownFailureMapsToPlaybackFailed(
        command: PlaybackCommandFeature.Command
    ) async {
        let requestID = UUID(0)
        let store = makeStore(command: command, requestID: requestID) {
            $0.musicProvider.play = { _ in
                throw TestError()
            }
            $0.musicProvider.resume = {
                throw TestError()
            }
        }

        await store.send(.start)
        await store.receive(.execute(command, requestID: requestID))
        await store.receive(
            .response(requestID: requestID, result: .failure(.playbackFailed))
        )
        await store.receive(
            .delegate(
                .completed(
                    requestID: requestID,
                    result: .failure(.playbackFailed)
                )
            )
        )
    }

    @Test
    func replacementCancelsFirstCommandAndCompletesLatestRequest() async {
        let firstItemID = makeItemID(nativeID: "first")
        let latestItemID = makeItemID(nativeID: "latest")
        let firstCancellationObserved = LockIsolated(false)
        let (firstStarted, firstStartedContinuation) = AsyncStream<Void>.makeStream()
        let store = makeStore(
            command: .play(firstItemID),
            requestID: UUID(0)
        ) {
            $0.musicProvider.play = { itemID in
                if itemID == firstItemID {
                    firstStartedContinuation.yield()
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch is CancellationError {
                        firstCancellationObserved.withValue { $0 = true }
                        throw CancellationError()
                    }
                }
            }
        }

        await store.send(.start)
        await store.receive(
            .execute(.play(firstItemID), requestID: UUID(0))
        )
        var iterator = firstStarted.makeAsyncIterator()
        _ = await iterator.next()

        await store.send(
            .replace(.play(latestItemID), requestID: UUID(1))
        )
        await store.receive(
            .execute(.play(latestItemID), requestID: UUID(1))
        ) {
            $0.command = .play(latestItemID)
            $0.requestID = UUID(1)
        }
        await store.receive(
            .response(
                requestID: UUID(1),
                result: .success(.play(latestItemID))
            )
        )
        await store.receive(
            .delegate(
                .completed(
                    requestID: UUID(1),
                    result: .success(.play(latestItemID))
                )
            )
        )

        #expect(firstCancellationObserved.value)
        firstStartedContinuation.finish()
    }

    @Test
    func staleResponsesDoNotDelegateOrChangeTheLatestRequest() async {
        let staleCommand = PlaybackCommandFeature.Command.play(
            makeItemID(nativeID: "stale-song")
        )
        let latestCommand = PlaybackCommandFeature.Command.resume(
            makeItemID(nativeID: "latest-song")
        )
        let latestState = PlaybackCommandFeature.State(
            command: latestCommand,
            requestID: UUID(1)
        )
        let store = TestStore(initialState: latestState) {
            PlaybackCommandFeature()
        }

        await store.send(
            .response(requestID: UUID(0), result: .success(staleCommand))
        )
        await store.send(
            .response(requestID: UUID(0), result: .failure(.network))
        )

        #expect(store.state == latestState)
    }

    // MARK: - Helpers

    private func makeStore(
        command: PlaybackCommandFeature.Command,
        requestID: UUID = UUID(0),
        configureDependencies: (inout DependencyValues) -> Void
    ) -> TestStoreOf<PlaybackCommandFeature> {
        TestStore(
            initialState: PlaybackCommandFeature.State(
                command: command,
                requestID: requestID
            )
        ) {
            PlaybackCommandFeature()
        } withDependencies: {
            configureDependencies(&$0)
        }
    }

    private func makeItemID(nativeID: String = "song-1") -> MusicItemID {
        MusicItemID(providerID: "fake", nativeID: nativeID)
    }

    private struct TestError: Error {}
}
