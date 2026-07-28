@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

struct AVFoundationPlaybackClientCompositionTests {
    /// Proves the four reducer-facing clients share one supplied player without
    /// exposing it or performing network-backed playback.
    @Test
    @MainActor
    func liveClientsShareOnePlayerWithoutExposingIt() async throws {
        let playCallCount = LockIsolated(0)
        let pauseCallCount = LockIsolated(0)
        let seekTimes = LockIsolated<[CMTime]>([])
        let player = PlaybackRecordingPlayer(
            playCallCount: playCallCount,
            pauseCallCount: pauseCallCount,
            seekTimes: seekTimes
        )
        let registry = AVPlayerItemRegistry()
        let preparedItem = AVPlayerItemFixture.make()
        let preparer = AVPlayerItemPreparer(
            loadIsPlayable: { _ in true },
            makeItem: { _ in preparedItem }
        )
        let installer = AVPlayerItemInstaller(player: player, registry: registry)
        let transport = AVPlayerTransport(player: player)
        let timeline = AVPlayerTimeline(player: player)
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live
        )

        let itemClient = PlaybackItemClient.live(
            preparer: preparer,
            installer: installer
        )
        let transportClient = PlaybackTransportClient.live(transport)
        let timelineClient = PlaybackTimelineClient.live(timeline)
        let observationClient = PlaybackObservationClient.live(observation)

        let url = try #require(URL(string: "memory://shared"))
        let trackID = TrackID(providerID: .jamendo, nativeID: "shared")
        let resource = PlaybackResource(
            trackID: trackID,
            location: .progressive(url)
        )

        #expect(player.currentItem == nil)

        try await itemClient.load(resource)

        #expect(player.currentItem === preparedItem)

        try await transportClient.play()
        try await transportClient.pause()
        try await timelineClient.seek(0)

        #expect(playCallCount.value == 1)
        #expect(pauseCallCount.value == 1)
        #expect(seekTimes.value.map(\.seconds) == [0])

        var iterator =
            await observationClient.observations().makeAsyncIterator()
        let first = await iterator.next()

        guard case .snapshot(let snapshot) = first else {
            Issue.record(
                "expected an initial snapshot reporting the shared player's registered track identity, got \(String(describing: first))"
            )
            return
        }
        #expect(snapshot.currentTrackID == trackID)
    }

    /// A rejected asset must not replace or register over the last confirmed
    /// player item.
    @Test
    @MainActor
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
        let client = PlaybackItemClient.live(
            preparer: preparer,
            installer: AVPlayerItemInstaller(
                player: player,
                registry: registry
            )
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
            try await client.load(resource)
        }

        #expect(makeItemCallCount.value == 0)
        #expect(player.currentItem === sentinelItem)
        #expect(registry.trackID(for: sentinelItem) == sentinelTrackID)
        #expect(registry.trackID(for: player.currentItem) != rejectedTrackID)
    }
}
