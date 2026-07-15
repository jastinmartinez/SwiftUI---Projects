import Testing

@testable import Crescendo

struct FakeMusicProviderTests {
    @Test
    func fakeReturnsConfiguredAccessAndResults() async throws {
        let expected = SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Test Song",
            artistName: "Test Artist",
            artworkURL: nil
        )
        let fake = FakeMusicProvider(
            access: .init(authorization: .authorized, playbackEligibility: .eligible),
            searchResults: [expected]
        )
        let musicProvider = await fake.client()

        #expect(
            await musicProvider.currentAccess()
                == .init(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
        )
        #expect(
            await musicProvider.requestAccess()
                == .init(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
        )
        #expect(try await musicProvider.search("test", 20) == [expected])
    }
}
