import Testing

@testable import Crescendo

struct AVPlayerItemRegistryTests {
    @Test
    @MainActor
    func registryMapsInstalledItemToTrackIdentity() {
        let registry = AVPlayerItemRegistry()
        let item = AVPlayerItemFixture.make()
        let trackID = TrackID(providerID: .library, nativeID: "42")

        registry.register(item, trackID: trackID)

        #expect(registry.trackID(for: item) == trackID)
        registry.remove(item)
        #expect(registry.trackID(for: item) == nil)
    }
}
