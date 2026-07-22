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
    func queueReplacementPreservesOrderAndStartsAtTheRequestedItem() async throws {
        let songs = [
            makeSong(nativeID: "1"),
            makeSong(nativeID: "2"),
            makeSong(nativeID: "3"),
        ]
        let fake = makeFakeProvider(searchResults: songs)
        let playbackQueue = await fake.playbackQueueClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackQueue.replace(songs.map(\.id), songs[1].id)

        let playbackSnapshot = await nextPlaybackSnapshot(from: playbackObservation)
        let queuedItemIDs = await fake.queuedItemIDs()

        #expect(queuedItemIDs == songs.map(\.id))
        #expect(playbackSnapshot?.currentItemID == songs[1].id)
        #expect(playbackSnapshot?.status == .playing)
        #expect(playbackSnapshot?.currentTime == 0)
    }

    @Test
    func queueTransitionsMoveTheProviderSnapshotWithoutChangingQueueOrder() async throws {
        let songs = [
            makeSong(nativeID: "1"),
            makeSong(nativeID: "2"),
            makeSong(nativeID: "3"),
        ]
        let fake = makeFakeProvider(searchResults: songs)
        let playbackQueue = await fake.playbackQueueClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackQueue.replace(songs.map(\.id), songs[1].id)
        try await playbackQueue.next()
        let nextSnapshot = await nextPlaybackSnapshot(from: playbackObservation)
        try await playbackQueue.previous()
        let previousSnapshot = await nextPlaybackSnapshot(from: playbackObservation)

        #expect(nextSnapshot?.currentItemID == songs[2].id)
        #expect(nextSnapshot?.currentTime == 0)
        #expect(previousSnapshot?.currentItemID == songs[1].id)
        #expect(await fake.queuedItemIDs() == songs.map(\.id))
    }

    @Test(arguments: [PlaybackQueueBoundary.first, .last])
    func queueTransitionAtBoundaryFailsWithoutChangingPlayback(
        boundary: PlaybackQueueBoundary
    ) async throws {
        let songs = [makeSong(nativeID: "1"), makeSong(nativeID: "2")]
        let fake = makeFakeProvider(searchResults: songs)
        let playbackQueue = await fake.playbackQueueClient()
        let playbackObservation = await fake.playbackObservationClient()
        let startingItem = boundary == .first ? songs[0] : songs[1]

        try await playbackQueue.replace(songs.map(\.id), startingItem.id)
        let previousSnapshot = await nextPlaybackSnapshot(from: playbackObservation)

        await expectUnavailable {
            switch boundary {
            case .first:
                try await playbackQueue.previous()
            case .last:
                try await playbackQueue.next()
            }
        }

        let currentSnapshot = await nextPlaybackSnapshot(from: playbackObservation)
        #expect(currentSnapshot == previousSnapshot)
    }

    @Test
    func emptyQueueDoesNotChangePlayback() async throws {
        let song = makeSong(nativeID: "1")

        try await assertUnavailableQueueDoesNotChangePlayback(
            configuredSongs: [song],
            itemIDs: [],
            startingItemID: song.id
        )
    }

    @Test
    func startingItemOutsideQueueDoesNotChangePlayback() async throws {
        let songs = [
            makeSong(nativeID: "1"),
            makeSong(nativeID: "2"),
        ]

        try await assertUnavailableQueueDoesNotChangePlayback(
            configuredSongs: songs,
            itemIDs: [songs[0].id],
            startingItemID: songs[1].id
        )
    }

    @Test
    func mixedProviderQueueDoesNotChangePlayback() async throws {
        let fakeSong = makeSong(nativeID: "1")
        let otherSong = makeSong(providerID: "other", nativeID: "2")

        try await assertUnavailableQueueDoesNotChangePlayback(
            configuredSongs: [fakeSong, otherSong],
            itemIDs: [fakeSong.id, otherSong.id],
            startingItemID: fakeSong.id
        )
    }

    @Test
    func unknownCachedItemDoesNotChangePlayback() async throws {
        let song = makeSong(nativeID: "1")
        let unknownItemID = MusicItemID(providerID: "fake", nativeID: "unknown")

        try await assertUnavailableQueueDoesNotChangePlayback(
            configuredSongs: [song],
            itemIDs: [song.id, unknownItemID],
            startingItemID: song.id
        )
    }

    @Test
    func resumePreservesSoughtTimeAndChangesStatusToPlaying() async throws {
        let fake = makeFakeProvider()
        let playbackTimeline = await fake.playbackTimelineClient()
        let playbackTransport = await fake.playbackTransportClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackTimeline.seek(42)
        try await playbackTransport.pause()
        let pausedPlaybackSnapshot = await nextPlaybackSnapshot(
            from: playbackObservation
        )
        try await playbackTransport.play()
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
        let playbackQueue = await fake.playbackQueueClient()
        let playbackTimeline = await fake.playbackTimelineClient()
        let playbackTransport = await fake.playbackTransportClient()
        let playbackObservation = await fake.playbackObservationClient()

        let itemID = MusicItemID(providerID: "fake", nativeID: "1")
        try await playbackQueue.replace([itemID], itemID)
        try await playbackTimeline.seek(42)
        try await playbackTransport.stop()
        let playbackSnapshot = await nextPlaybackSnapshot(from: playbackObservation)

        #expect(playbackSnapshot?.status == .stopped)
        #expect(playbackSnapshot?.currentTime == 0)
    }

    // MARK: - Helpers

    enum PlaybackQueueBoundary {
        case first
        case last
    }

    private func makeFakeProvider() -> FakeMusicProvider {
        makeFakeProvider(searchResults: [makeSong(nativeID: "1")])
    }

    private func makeFakeProvider(
        searchResults: [SongSummary]
    ) -> FakeMusicProvider {
        FakeMusicProvider(
            access: .init(authorization: .authorized, playbackEligibility: .eligible),
            searchResults: searchResults
        )
    }

    private func makeSong(
        providerID: ProviderID = "fake",
        nativeID: String
    ) -> SongSummary {
        SongSummary(
            id: .init(providerID: providerID, nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }

    private func nextPlaybackSnapshot(
        from playbackObservation: PlaybackObservationClient
    ) async -> PlaybackSnapshot? {
        let snapshots = await playbackObservation.playbackSnapshots()
        var iterator = snapshots.makeAsyncIterator()
        return await iterator.next()
    }

    private func assertUnavailableQueueDoesNotChangePlayback(
        configuredSongs: [SongSummary],
        itemIDs: [MusicItemID],
        startingItemID: MusicItemID
    ) async throws {
        let currentSong = try #require(configuredSongs.first)
        let fake = makeFakeProvider(searchResults: configuredSongs)
        let playbackQueue = await fake.playbackQueueClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackQueue.replace([currentSong.id], currentSong.id)
        let previousSnapshot = await nextPlaybackSnapshot(
            from: playbackObservation
        )
        let previousQueue = await fake.queuedItemIDs()

        await expectUnavailable {
            try await playbackQueue.replace(itemIDs, startingItemID)
        }

        let currentSnapshot = await nextPlaybackSnapshot(
            from: playbackObservation
        )
        let currentQueue = await fake.queuedItemIDs()

        #expect(currentSnapshot == previousSnapshot)
        #expect(currentQueue == previousQueue)
    }

    private func expectUnavailable(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected MusicProviderError.unavailable")
        } catch let error as MusicProviderError {
            #expect(error == .unavailable)
        } catch {
            Issue.record("Expected MusicProviderError.unavailable, received \(error)")
        }
    }
}
