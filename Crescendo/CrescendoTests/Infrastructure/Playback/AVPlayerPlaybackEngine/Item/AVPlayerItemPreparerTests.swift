import Foundation
import Testing

@testable import Crescendo

struct AVPlayerItemPreparerTests {
    @Test
    @MainActor
    func unplayableURLFailsPreparation() async throws {
        let url = try #require(URL(string: "https://example.com/audio.mp3"))
        let preparer = AVPlayerItemPreparer(
            loadIsPlayable: { _ in false },
            makeItem: { _ in AVPlayerItemFixture.make() }
        )

        await #expect(throws: PlaybackFailure.self) {
            _ = try await preparer.prepare(url)
        }
    }
}
