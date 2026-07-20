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

    @Test
    func playStartsAtTimeZero() async throws {
        let fake = makeFakeProvider()
        let musicProvider = await fake.client()

        try await musicProvider.seek(42)
        try await musicProvider.play(.init(providerID: "fake", nativeID: "1"))
        let playbackSnapshot = await nextPlaybackSnapshot(from: musicProvider)

        #expect(playbackSnapshot?.status == .playing)
        #expect(playbackSnapshot?.currentTime == 0)
    }

    @Test
    func resumePreservesSoughtTimeAndChangesStatusToPlaying() async throws {
        let fake = makeFakeProvider()
        let musicProvider = await fake.client()

        try await musicProvider.seek(42)
        try await musicProvider.pause()
        let pausedPlaybackSnapshot = await nextPlaybackSnapshot(from: musicProvider)
        try await musicProvider.resume()
        let resumedPlaybackSnapshot = await nextPlaybackSnapshot(from: musicProvider)

        #expect(pausedPlaybackSnapshot?.status == .paused)
        #expect(pausedPlaybackSnapshot?.currentTime == 42)
        #expect(resumedPlaybackSnapshot?.status == .playing)
        #expect(resumedPlaybackSnapshot?.currentTime == 42)
    }

    @Test
    func stopResetsPositionToZero() async throws {
        let fake = makeFakeProvider()
        let musicProvider = await fake.client()

        try await musicProvider.play(.init(providerID: "fake", nativeID: "1"))
        try await musicProvider.seek(42)
        try await musicProvider.stop()
        let playbackSnapshot = await nextPlaybackSnapshot(from: musicProvider)

        #expect(playbackSnapshot?.status == .stopped)
        #expect(playbackSnapshot?.currentTime == 0)
    }

    // MARK: - Helpers

    private func makeFakeProvider() -> FakeMusicProvider {
        FakeMusicProvider(
            access: .init(authorization: .authorized, playbackEligibility: .eligible),
            searchResults: []
        )
    }

    private func nextPlaybackSnapshot(
        from musicProvider: MusicProviderClient
    ) async -> MusicPlaybackSnapshot? {
        let snapshots = await musicProvider.playbackSnapshots()
        var iterator = snapshots.makeAsyncIterator()
        return await iterator.next()
    }
}
