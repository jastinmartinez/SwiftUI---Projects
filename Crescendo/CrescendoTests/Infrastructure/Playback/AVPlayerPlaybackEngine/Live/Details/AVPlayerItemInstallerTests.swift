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
            try installer.install(
                item,
                for: resource,
                installation: PlaybackItemInstallation(id: UUID(0))
            )
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
    func rollbackRestoresPreviousItemAndRegistryIdentity() throws {
        let previousItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: previousItem)
        let registry = AVPlayerItemRegistry()
        let previousTrackID = TrackID(
            providerID: .localMusic,
            nativeID: "previous"
        )
        registry.register(
            previousItem,
            trackID: previousTrackID
        )
        let installer = AVPlayerItemInstaller(player: player, registry: registry)
        let newItem = AVPlayerItemFixture.make()
        let url = try #require(URL(string: "https://example.com/new.mp3"))
        let resource = PlaybackResource(
            trackID: TrackID(providerID: .jamendo, nativeID: "new"),
            location: .progressive(url)
        )
        let installation = PlaybackItemInstallation(id: UUID(0))

        try installer.install(
            newItem,
            for: resource,
            installation: installation
        )
        installer.rollback(installation)

        #expect(player.currentItem === previousItem)
        #expect(registry.trackID(for: previousItem) == previousTrackID)
        #expect(registry.trackID(for: newItem) == nil)
    }

    @Test
    @MainActor
    func commitKeepsTargetAndReleasesPreviousRegistryIdentity() throws {
        let previousItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: previousItem)
        let registry = AVPlayerItemRegistry()
        registry.register(
            previousItem,
            trackID: TrackID(providerID: .localMusic, nativeID: "previous")
        )
        let installer = AVPlayerItemInstaller(player: player, registry: registry)
        let targetItem = AVPlayerItemFixture.make()
        let targetTrackID = TrackID(
            providerID: .jamendo,
            nativeID: "target"
        )
        let resource = try PlaybackResource(
            trackID: targetTrackID,
            location: .progressive(
                #require(URL(string: "https://example.com/target.mp3"))
            )
        )
        let installation = PlaybackItemInstallation(id: UUID(0))

        try installer.install(
            targetItem,
            for: resource,
            installation: installation
        )
        installer.commit(installation)

        #expect(player.currentItem === targetItem)
        #expect(registry.trackID(for: targetItem) == targetTrackID)
        #expect(registry.trackID(for: previousItem) == nil)
    }

    @Test
    @MainActor
    func staleCommitAndRollbackCannotAffectNewerInstallation() throws {
        let confirmedItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: confirmedItem)
        let registry = AVPlayerItemRegistry()
        let confirmedTrackID = TrackID(
            providerID: .localMusic,
            nativeID: "confirmed"
        )
        registry.register(
            confirmedItem,
            trackID: confirmedTrackID
        )
        let installer = AVPlayerItemInstaller(player: player, registry: registry)
        let firstItem = AVPlayerItemFixture.make()
        let firstInstallation = PlaybackItemInstallation(id: UUID(0))
        let firstResource = try PlaybackResource(
            trackID: TrackID(providerID: .jamendo, nativeID: "first"),
            location: .progressive(
                #require(URL(string: "https://example.com/first.mp3"))
            )
        )
        let secondItem = AVPlayerItemFixture.make()
        let secondInstallation = PlaybackItemInstallation(id: UUID(1))
        let secondResource = try PlaybackResource(
            trackID: TrackID(providerID: .jamendo, nativeID: "second"),
            location: .progressive(
                #require(URL(string: "https://example.com/second.mp3"))
            )
        )

        try installer.install(
            firstItem,
            for: firstResource,
            installation: firstInstallation
        )
        try installer.install(
            secondItem,
            for: secondResource,
            installation: secondInstallation
        )

        installer.rollback(firstInstallation)
        installer.commit(firstInstallation)

        #expect(player.currentItem === secondItem)
        #expect(registry.trackID(for: secondItem) == secondResource.trackID)

        installer.rollback(secondInstallation)

        #expect(player.currentItem === confirmedItem)
        #expect(registry.trackID(for: confirmedItem) == confirmedTrackID)
        #expect(registry.trackID(for: firstItem) == nil)
        #expect(registry.trackID(for: secondItem) == nil)
    }
}
