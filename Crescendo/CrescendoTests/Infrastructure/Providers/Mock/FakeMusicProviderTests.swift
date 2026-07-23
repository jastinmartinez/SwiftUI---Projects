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
        let currentAccess = await accessClient.currentAccess("fake")
        let requestedAccess = await accessClient.requestAccess("fake")

        #expect(currentAccess == expectedAccess)
        #expect(requestedAccess == expectedAccess)
    }

    @Test
    func searchClientPaginatesConfiguredResults() async throws {
        let tracks = (1...4).map { makeTrack(nativeID: String($0)) }
        let fake = FakeMusicProvider(
            access: .init(
                authorization: .authorized,
                playbackEligibility: .eligible
            ),
            searchResults: tracks
        )
        let client = await fake.searchClient()

        let firstPage = try await client.searchPage(
            "fake",
            .initial(query: "test"),
            2
        )
        let cursor = try #require(firstPage.nextCursor)
        let continuation = try await client.searchPage(
            "fake",
            .continuation(cursor),
            2
        )

        #expect(firstPage.tracks.map(\.id) == Array(tracks.prefix(2)).map(\.id))
        let expectedSongs = Array(tracks.dropFirst(2).prefix(2))
        #expect(continuation.tracks.map(\.id) == expectedSongs.map(\.id))
        #expect(continuation.nextCursor == nil)
    }

    @Test
    func queueReplacementPreservesOrderAndStartsAtTheRequestedItem() async throws {
        let tracks = [
            makeTrack(nativeID: "1"),
            makeTrack(nativeID: "2"),
            makeTrack(nativeID: "3"),
        ]
        let fake = makeFakeProvider(searchResults: tracks)
        let playbackQueue = await fake.playbackQueueClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackQueue.replace(tracks.map(\.id), tracks[1].id)

        let playbackSnapshot = await nextPlaybackSnapshot(from: playbackObservation)
        let queuedItemIDs = await fake.queuedItemIDs()

        #expect(queuedItemIDs == tracks.map(\.id))
        #expect(playbackSnapshot?.currentTrackID == tracks[1].id)
        #expect(playbackSnapshot?.status == .playing)
        #expect(playbackSnapshot?.currentTime == 0)
    }

    @Test
    func queueTransitionsMoveTheProviderSnapshotWithoutChangingQueueOrder() async throws {
        let tracks = [
            makeTrack(nativeID: "1"),
            makeTrack(nativeID: "2"),
            makeTrack(nativeID: "3"),
        ]
        let fake = makeFakeProvider(searchResults: tracks)
        let playbackQueue = await fake.playbackQueueClient()
        let playbackObservation = await fake.playbackObservationClient()

        try await playbackQueue.replace(tracks.map(\.id), tracks[1].id)
        let nextResult = try await playbackQueue.navigate(.next)
        let nextSnapshot = await nextPlaybackSnapshot(from: playbackObservation)
        let previousResult = try await playbackQueue.navigate(.previous)
        let previousSnapshot = await nextPlaybackSnapshot(from: playbackObservation)

        #expect(nextResult == .accepted)
        #expect(previousResult == .accepted)
        #expect(nextSnapshot?.currentTrackID == tracks[2].id)
        #expect(nextSnapshot?.currentTime == 0)
        #expect(previousSnapshot?.currentTrackID == tracks[1].id)
        #expect(await fake.queuedItemIDs() == tracks.map(\.id))
    }

    @Test(arguments: [PlaybackQueueBoundary.first, .last])
    func queueTransitionAtBoundaryDoesNotChangePlayback(
        boundary: PlaybackQueueBoundary
    ) async throws {
        let tracks = [makeTrack(nativeID: "1"), makeTrack(nativeID: "2")]
        let fake = makeFakeProvider(searchResults: tracks)
        let playbackQueue = await fake.playbackQueueClient()
        let playbackObservation = await fake.playbackObservationClient()
        let startingItem = boundary == .first ? tracks[0] : tracks[1]

        try await playbackQueue.replace(tracks.map(\.id), startingItem.id)
        let previousSnapshot = await nextPlaybackSnapshot(from: playbackObservation)

        let result: PlaybackQueueNavigationResult
        switch boundary {
        case .first:
            result = try await playbackQueue.navigate(.previous)
        case .last:
            result = try await playbackQueue.navigate(.next)
        }

        let currentSnapshot = await nextPlaybackSnapshot(from: playbackObservation)
        #expect(result == .boundaryReached)
        #expect(currentSnapshot == previousSnapshot)
    }

    @Test
    func queueClientUpdatesProviderConfirmedModes() async throws {
        let song = makeTrack(nativeID: "1")
        let fake = makeFakeProvider(searchResults: [song])
        let queue = await fake.playbackQueueClient()
        let observation = await fake.playbackObservationClient()

        try await queue.replace([song.id], song.id)
        try await queue.setRepeat(.one)
        try await queue.setShuffle(.songs)

        let snapshot = await nextPlaybackSnapshot(from: observation)
        #expect(snapshot?.repeatMode == .one)
        #expect(snapshot?.shuffleMode == .songs)
    }

    @Test
    func emptyQueueDoesNotChangePlayback() async throws {
        let song = makeTrack(nativeID: "1")

        try await assertUnavailableQueueDoesNotChangePlayback(
            configuredSongs: [song],
            itemIDs: [],
            startingItemID: song.id
        )
    }

    @Test
    func startingItemOutsideQueueDoesNotChangePlayback() async throws {
        let tracks = [
            makeTrack(nativeID: "1"),
            makeTrack(nativeID: "2"),
        ]

        try await assertUnavailableQueueDoesNotChangePlayback(
            configuredSongs: tracks,
            itemIDs: [tracks[0].id],
            startingItemID: tracks[1].id
        )
    }

    @Test
    func mixedProviderQueueDoesNotChangePlayback() async throws {
        let fakeSong = makeTrack(nativeID: "1")
        let otherSong = makeTrack(providerID: "other", nativeID: "2")

        try await assertUnavailableQueueDoesNotChangePlayback(
            configuredSongs: [fakeSong, otherSong],
            itemIDs: [fakeSong.id, otherSong.id],
            startingItemID: fakeSong.id
        )
    }

    @Test
    func unknownCachedItemDoesNotChangePlayback() async throws {
        let song = makeTrack(nativeID: "1")
        let unknownItemID = TrackID(providerID: "fake", nativeID: "unknown")

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

        let itemID = TrackID(providerID: "fake", nativeID: "1")
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
        makeFakeProvider(searchResults: [makeTrack(nativeID: "1")])
    }

    private func makeFakeProvider(
        searchResults: [Track]
    ) -> FakeMusicProvider {
        FakeMusicProvider(
            access: .init(authorization: .authorized, playbackEligibility: .eligible),
            searchResults: searchResults
        )
    }

    private func makeTrack(
        providerID: ProviderID = "fake",
        nativeID: String
    ) -> Track {
        Track(
            id: .init(providerID: providerID, nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            albumTitle: nil,
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
        configuredSongs: [Track],
        itemIDs: [TrackID],
        startingItemID: TrackID
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
