@preconcurrency import AVFoundation
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppCompositionTests {
    @Test
    func liveStoreStartsOnSearchWithAnEmptyIdleLibrary() {
        let store = AppComposition.live(
            jamendoClientID: nil,
            audiusAPIKey: nil,
            player: AVPlayer(),
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { _ in AVPlayerItemFixture.make() }
            ),
            data: { _ in throw MusicProviderError.network },
            applicationSupportURL: URL.temporaryDirectory.appending(
                path: "AppCompositionTests"
            )
        ).store()

        #expect(store.selectedTab == .search)
        #expect(store.library.library.items.isEmpty)
        #expect(store.library.loadStatus == .idle)
    }
}
