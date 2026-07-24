@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import Crescendo

struct AVPlayerItemInstallerTests {
    /// A task cancelled before it runs still races against the cooperative
    /// scheduler, but `.cancel()` called synchronously right after `Task {
    /// ... }` is created always wins: the calling context hasn't suspended
    /// yet, so the new task's body cannot start until this test function
    /// itself awaits `task.value`. `install`'s first line rechecks
    /// cancellation, so the player is provably never mutated.
    @Test
    @MainActor
    func cancelledInstallationLeavesCurrentItemUntouched() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let installer = AVPlayerItemInstaller(player: player, registry: registry)
        let item = AVPlayerItemFixture.make()
        let url = try #require(URL(string: "https://example.com/audio.mp3"))
        let resource = PlaybackResource(
            trackID: TrackID(providerID: .jamendo, nativeID: "cancelled"),
            location: .progressive(url)
        )

        let task = Task { @MainActor in
            try installer.install(item, for: resource)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(player.currentItem == nil)
        #expect(registry.trackID(for: item) == nil)
    }

    @Test
    @MainActor
    func installReplacesCurrentItemAndUpdatesRegistryIdentity() throws {
        let previousItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: previousItem)
        let registry = AVPlayerItemRegistry()
        registry.register(
            previousItem,
            trackID: TrackID(providerID: .localMusic, nativeID: "previous")
        )
        let installer = AVPlayerItemInstaller(player: player, registry: registry)
        let newItem = AVPlayerItemFixture.make()
        let url = try #require(URL(string: "https://example.com/new.mp3"))
        let resource = PlaybackResource(
            trackID: TrackID(providerID: .jamendo, nativeID: "new"),
            location: .progressive(url)
        )

        try installer.install(newItem, for: resource)

        #expect(player.currentItem === newItem)
        #expect(registry.trackID(for: newItem) == resource.trackID)
        #expect(registry.trackID(for: previousItem) == nil)
    }
}
