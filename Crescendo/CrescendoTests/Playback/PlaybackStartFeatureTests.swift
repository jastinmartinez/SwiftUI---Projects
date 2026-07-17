import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackStartFeatureTests {
    @Test
    func successfulStartPlaysItemOnceAndDelegatesItsIdentity() async {
        let itemID = makeItemID()
        let playedItemIDs = LockIsolated<[MusicItemID]>([])
        let store = makeStore(itemID: itemID) { receivedItemID in
            playedItemIDs.withValue { $0.append(receivedItemID) }
        }

        await store.send(.start)
        await store.receive(.playSucceeded)
        await store.receive(.delegate(.succeeded(itemID)))

        #expect(playedItemIDs.value == [itemID])
    }

    @Test
    func providerFailurePreservesTypedErrorAndItemIdentity() async {
        let itemID = makeItemID()
        let store = makeStore(itemID: itemID) { _ in
            throw MusicProviderError.network
        }

        await store.send(.start)
        await store.receive(.playFailed(.network))
        await store.receive(.delegate(.failed(itemID, .network)))
    }

    @Test
    func unknownFailureMapsToPlaybackFailed() async {
        let itemID = makeItemID()
        let store = makeStore(itemID: itemID) { _ in
            throw TestError()
        }

        await store.send(.start)
        await store.receive(.playFailed(.playbackFailed))
        await store.receive(.delegate(.failed(itemID, .playbackFailed)))
    }

    // MARK: - Helpers

    private func makeStore(
        itemID: MusicItemID,
        play: @escaping @Sendable (MusicItemID) async throws -> Void
    ) -> TestStoreOf<PlaybackStartFeature> {
        TestStore(
            initialState: PlaybackStartFeature.State(itemID: itemID)
        ) {
            PlaybackStartFeature()
        } withDependencies: {
            $0.musicProvider.play = play
        }
    }

    private func makeItemID() -> MusicItemID {
        MusicItemID(providerID: "fake", nativeID: "song-1")
    }

    private struct TestError: Error {}
}
