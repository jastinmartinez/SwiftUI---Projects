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
        let resource = PlaybackResource(
            trackID: trackID,
            location: .progressive(
                try #require(URL(string: "memory://shared"))
            )
        )

        #expect(player.currentItem == nil)

        try await engine.item.load(resource)
        try await engine.transport.play()
        try await engine.transport.stop()
        try await engine.timeline.seek(0)

        #expect(player.currentItem === preparedItem)
        #expect(playCallCount.value == 1)
        #expect(pauseCallCount.value == 1)
        #expect(seekTimes.value.map(\.seconds) == [0])

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
        let resource = PlaybackResource(
            trackID: rejectedTrackID,
            location: .progressive(
                try #require(URL(string: "memory://rejected"))
            )
        )

        await #expect(throws: PlaybackFailure.unsupportedResource) {
            try await engine.item.load(resource)
        }

        #expect(makeItemCallCount.value == 0)
        #expect(player.currentItem === sentinelItem)
        #expect(registry.trackID(for: sentinelItem) == sentinelTrackID)
        #expect(registry.trackID(for: player.currentItem) != rejectedTrackID)
    }
}
