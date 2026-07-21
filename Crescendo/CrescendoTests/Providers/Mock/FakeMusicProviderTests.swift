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
        let accessClient = await fake.accessClient()
        let searchClient = await fake.searchClient()
        let currentAccess = await accessClient.currentAccess()
        let requestedAccess = await accessClient.requestAccess()
        let searchResults = try await searchClient.search("test", 20)

        #expect(currentAccess == expectedAccess)
        #expect(requestedAccess == expectedAccess)
        #expect(searchResults == [expectedSong])
    }

    @Test
    func playStartsAtTimeZero() async throws {
        let fake = makeFakeProvider()
        let playbackControl = await fake.playbackControlClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackControl.seek(42)
        try await playbackControl.play(.init(providerID: "fake", nativeID: "1"))
        let playbackSnapshot = await nextPlaybackSnapshot(from: playbackObservation)

        #expect(playbackSnapshot?.status == .playing)
        #expect(playbackSnapshot?.currentTime == 0)
    }

    @Test
    func resumePreservesSoughtTimeAndChangesStatusToPlaying() async throws {
        let fake = makeFakeProvider()
        let playbackControl = await fake.playbackControlClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackControl.seek(42)
        try await playbackControl.pause()
        let pausedPlaybackSnapshot = await nextPlaybackSnapshot(
            from: playbackObservation
        )
        try await playbackControl.resume()
        let resumedPlaybackSnapshot = await nextPlaybackSnapshot(
            from: playbackObservation
        )

        #expect(pausedPlaybackSnapshot?.status == .paused)
        #expect(pausedPlaybackSnapshot?.currentTime == 42)
        #expect(resumedPlaybackSnapshot?.status == .playing)
        #expect(resumedPlaybackSnapshot?.currentTime == 42)
    }

    @Test
    func stopResetsPositionToZero() async throws {
        let fake = makeFakeProvider()
        let playbackControl = await fake.playbackControlClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackControl.play(.init(providerID: "fake", nativeID: "1"))
        try await playbackControl.seek(42)
        try await playbackControl.stop()
        let playbackSnapshot = await nextPlaybackSnapshot(from: playbackObservation)

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
        from playbackObservation: PlaybackObservationClient
    ) async -> MusicPlaybackSnapshot? {
        let snapshots = await playbackObservation.playbackSnapshots()
        var iterator = snapshots.makeAsyncIterator()
        return await iterator.next()
    }
}
