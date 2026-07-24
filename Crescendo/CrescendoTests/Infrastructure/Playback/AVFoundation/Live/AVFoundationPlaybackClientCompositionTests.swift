@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import Crescendo

struct AVFoundationPlaybackClientCompositionTests {
    /// Proves the four reducer-facing clients share one player without any of
    /// them exposing it: loading through `PlaybackItemClient.live` changes the
    /// supplied player's `currentItem`, and `PlaybackObservationClient.live`
    /// reports the same registered identity. The injected preparer returns
    /// `true` without touching the resource URL, so no network access occurs.
    @Test
    @MainActor
    func liveClientsShareOnePlayerWithoutExposingIt() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let preparer = AVPlayerItemPreparer(loadIsPlayable: { _ in true })
        let installer = AVPlayerItemInstaller(player: player, registry: registry)
        let transport = AVPlayerTransport(player: player)
        let timeline = AVPlayerTimeline(player: player)
        let observation = AVPlayerObservation(player: player, registry: registry)

        let itemClient = PlaybackItemClient.live(
            preparer: preparer,
            installer: installer
        )
        let transportClient = PlaybackTransportClient.live(transport)
        let timelineClient = PlaybackTimelineClient.live(timeline)
        let observationClient = PlaybackObservationClient.live(observation)

        let url = try #require(URL(string: "https://example.com/audio.mp3"))
        let trackID = TrackID(providerID: .jamendo, nativeID: "shared")
        let resource = PlaybackResource(
            trackID: trackID,
            location: .progressive(url)
        )

        #expect(player.currentItem == nil)

        try await itemClient.load(resource)

        #expect(player.currentItem != nil)

        // The transport and timeline clients operate on the same player without
        // exposing it; exercising them proves they do not create their own.
        try await transportClient.play()
        try await transportClient.pause()
        try await timelineClient.seek(0)

        var iterator = await observationClient.observations().makeAsyncIterator()
        let first = await iterator.next()

        guard case .snapshot(let snapshot) = first else {
            Issue.record(
                "expected an initial snapshot reporting the shared player's registered track identity, got \(String(describing: first))"
            )
            return
        }
        #expect(snapshot.currentTrackID == trackID)
    }
}
