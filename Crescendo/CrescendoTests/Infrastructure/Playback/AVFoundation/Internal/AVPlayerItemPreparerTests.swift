import Foundation
import Testing

@testable import Crescendo

struct AVPlayerItemPreparerTests {
    @Test
    @MainActor
    func unplayableResourceFailsPreparation() async throws {
        let url = try #require(URL(string: "https://example.com/audio.mp3"))
        let resource = PlaybackResource(
            trackID: TrackID(providerID: .jamendo, nativeID: "missing"),
            location: .progressive(url)
        )
        let preparer = AVPlayerItemPreparer(
            loadIsPlayable: { _ in false }
        )

        await #expect(throws: PlaybackFailure.self) {
            _ = try await preparer.prepare(resource)
        }
    }
}
