@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AVPlayerPlaybackEngineTests {
    /// Proves every reducer-facing client returned by the engine shares the
    /// supplied player without exposing that implementation detail.
    @Test
    func liveEngineClientsShareOnePlayerWithoutExposingIt() async throws {
        let playCallCount = LockIsolated(0)
        let pauseCallCount = LockIsolated(0)
        let seekTimes = LockIsolated<[CMTime]>([])
        let player = PlaybackRecordingPlayer(
            playCallCount: playCallCount,
            pauseCallCount: pauseCallCount,
            seekTimes: seekTimes
        )
        let preparedItem = AVPlayerItemFixture.make()
        let preparer = AVPlayerItemPreparer(
            loadIsPlayable: { _ in true },
            makeItem: { _ in preparedItem }
        )
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: preparer
        )
        let trackID = TrackID(providerID: .jamendo, nativeID: "shared")
        let resource = try PlaybackResource(
            trackID: trackID,
            location: .progressive(
                #require(URL(string: "memory://shared"))
            )
        )

        #expect(player.currentItem == nil)

        let installation = PlaybackItemInstallation(id: UUID(0))
        try await engine.item.load(resource, installation)
        try await engine.transport.play()
        let stopOutcome = await engine.transport.stop()

        #expect(player.currentItem === preparedItem)
        #expect(playCallCount.value == 1)
        #expect(pauseCallCount.value == 1)
        #expect(seekTimes.value.map(\.seconds) == [0])
        #expect(stopOutcome == .completed)

        var iterator =
            await engine.observation.observations().makeAsyncIterator()
        let first = await iterator.next()

        guard case .snapshot(let snapshot) = first else {
            Issue.record(
                "expected the shared player to emit its registered track identity"
            )
            return
        }
        #expect(snapshot.currentTrackID == trackID)

        await engine.item.commit(installation)
    }

    /// A rejected asset must not replace or register over the last confirmed
    /// player item.
    @Test
    func failedPreparationPreservesInstalledItemAndRegistry() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let sentinelItem = AVPlayerItemFixture.make()
        let sentinelTrackID = TrackID(
            providerID: .jamendo,
            nativeID: "sentinel"
        )
        registry.register(sentinelItem, trackID: sentinelTrackID)
        player.replaceCurrentItem(with: sentinelItem)

        let makeItemCallCount = LockIsolated(0)
        let preparer = AVPlayerItemPreparer(
            loadIsPlayable: { _ in false },
            makeItem: { _ in
                makeItemCallCount.withValue { $0 += 1 }
                return AVPlayerItemFixture.make()
            }
        )
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: preparer,
            registry: registry
        )
        let rejectedTrackID = TrackID(
            providerID: .jamendo,
            nativeID: "rejected"
        )
        let resource = try PlaybackResource(
            trackID: rejectedTrackID,
            location: .progressive(
                #require(URL(string: "memory://rejected"))
            )
        )

        await #expect(throws: PlaybackFailure.unsupportedResource) {
            try await engine.item.load(
                resource,
                PlaybackItemInstallation(id: UUID(0))
            )
        }

        #expect(makeItemCallCount.value == 0)
        #expect(player.currentItem === sentinelItem)
        #expect(registry.trackID(for: sentinelItem) == sentinelTrackID)
        #expect(registry.trackID(for: player.currentItem) != rejectedTrackID)
    }

    @Test
    func liveItemClientRollbackRestoresConfirmedPlayerIdentity() async throws {
        let confirmedItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: confirmedItem)
        let registry = AVPlayerItemRegistry()
        let confirmedTrackID = TrackID(
            providerID: .localMusic,
            nativeID: "confirmed"
        )
        registry.register(confirmedItem, trackID: confirmedTrackID)
        let targetItem = AVPlayerItemFixture.make()
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { _ in targetItem }
            ),
            registry: registry
        )
        let targetTrackID = TrackID(
            providerID: .jamendo,
            nativeID: "target"
        )
        let resource = try PlaybackResource(
            trackID: targetTrackID,
            location: .progressive(
                #require(URL(string: "memory://target"))
            )
        )
        let installation = PlaybackItemInstallation(id: UUID(0))

        try await engine.item.load(resource, installation)
        await engine.item.rollback(installation)

        #expect(player.currentItem === confirmedItem)
        #expect(registry.trackID(for: confirmedItem) == confirmedTrackID)
        #expect(registry.trackID(for: targetItem) == nil)
    }
}
