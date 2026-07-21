import Testing

@testable import Crescendo

struct FakeMusicProviderTests {
    @Test
    func fakeReturnsConfiguredAccess() async {
        let expectedAccess = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let fake = FakeMusicProvider(
            access: expectedAccess,
            searchResults: []
        )
        let accessClient = await fake.accessClient()
        let currentAccess = await accessClient.currentAccess()
        let requestedAccess = await accessClient.requestAccess()

        #expect(currentAccess == expectedAccess)
        #expect(requestedAccess == expectedAccess)
    }

    @Test
    func searchClientPaginatesConfiguredResults() async throws {
        let songs = (1...4).map { makeSong(nativeID: String($0)) }
        let fake = FakeMusicProvider(
            access: .init(
                authorization: .authorized,
                playbackEligibility: .eligible
            ),
            searchResults: songs
        )
        let client = await fake.searchClient()

        let firstPage = try await client.searchPage(
            .initial(query: "test"),
            2
        )
        let cursor = try #require(firstPage.nextCursor)
        let continuation = try await client.searchPage(
            .continuation(cursor),
            2
        )

        #expect(firstPage.songs.map(\.id) == Array(songs.prefix(2)).map(\.id))
        #expect(
            continuation.songs.map(\.id)
                == Array(songs.dropFirst(2).prefix(2)).map(\.id)
        )
        #expect(continuation.nextCursor == nil)
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

    private func makeSong(nativeID: String) -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
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
