import Testing

@testable import Crescendo

struct FakeMusicProviderTests {
    @Test
    func fakeReturnsConfiguredAccessAndResults() async throws {
        let expectedSong = SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Test Song",
            artistName: "Test Artist",
            artworkURL: nil,
            duration: nil
        )
        let expectedAccess = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let fake = FakeMusicProvider(
            access: expectedAccess,
            searchResults: [expectedSong]
        )
        let musicProvider = await fake.client()
        let currentAccess = await musicProvider.currentAccess()
        let requestedAccess = await musicProvider.requestAccess()
        let searchResults = try await musicProvider.search("test", 20)

        #expect(currentAccess == expectedAccess)
        #expect(requestedAccess == expectedAccess)
        #expect(searchResults == [expectedSong])
    }
}
