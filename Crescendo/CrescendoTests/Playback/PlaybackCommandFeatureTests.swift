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
        let store = makeStore(command: command) {
            $0.musicProvider.play = { receivedItemID in
                playedItemIDs.withValue { $0.append(receivedItemID) }
            }
            $0.musicProvider.resume = {
                resumeCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.start)
        await store.receive(.commandSucceeded)
        await store.receive(.delegate(.succeeded(command)))

        #expect(playedItemIDs.value == [itemID])
        #expect(resumeCallCount.value == 0)
    }

    @Test
    func resumeCommandCallsResumeOnlyAndDelegatesItsCommand() async {
        let itemID = makeItemID()
        let playedItemIDs = LockIsolated<[MusicItemID]>([])
        let resumeCallCount = LockIsolated(0)
        let command = PlaybackCommandFeature.Command.resume(itemID)
        let store = makeStore(command: command) {
            $0.musicProvider.play = { receivedItemID in
                playedItemIDs.withValue { $0.append(receivedItemID) }
            }
            $0.musicProvider.resume = {
                resumeCallCount.withValue { $0 += 1 }
            }
        }

        await store.send(.start)
        await store.receive(.commandSucceeded)
        await store.receive(.delegate(.succeeded(command)))

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
        let store = makeStore(command: command) {
            $0.musicProvider.play = { _ in
                throw MusicProviderError.network
            }
            $0.musicProvider.resume = {
                throw MusicProviderError.network
            }
        }

        await store.send(.start)
        await store.receive(.commandFailed(.network))
        await store.receive(.delegate(.failed(command, .network)))
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
        let store = makeStore(command: command) {
            $0.musicProvider.play = { _ in
                throw TestError()
            }
            $0.musicProvider.resume = {
                throw TestError()
            }
        }

        await store.send(.start)
        await store.receive(.commandFailed(.playbackFailed))
        await store.receive(.delegate(.failed(command, .playbackFailed)))
    }

    // MARK: - Helpers

    private func makeStore(
        command: PlaybackCommandFeature.Command,
        configureDependencies: (inout DependencyValues) -> Void
    ) -> TestStoreOf<PlaybackCommandFeature> {
        TestStore(
            initialState: PlaybackCommandFeature.State(command: command)
        ) {
            PlaybackCommandFeature()
        } withDependencies: {
            configureDependencies(&$0)
        }
    }

    private func makeItemID() -> MusicItemID {
        MusicItemID(providerID: "fake", nativeID: "song-1")
    }

    private struct TestError: Error {}
}
