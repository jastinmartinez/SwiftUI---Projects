import Foundation
@preconcurrency import MusicKit

/// Owns Apple Music authorization, catalog access, playback, mapping, and session caches.
actor AppleMusicProvider {
    /// The stable application-owned identifier for Apple Music.
    static let providerID: ProviderID = .appleMusic

    private let player = ApplicationMusicPlayer.shared
    private var songsByNativeID: [String: Song] = [:]

    /// Resolves the player's current queue entry into provider-neutral identity.
    private var currentItemID: MusicItemID? {
        guard let nativeID = player.queue.currentEntry?.item?.id.rawValue else {
            return nil
        }
        return MusicItemID(
            providerID: Self.providerID,
            nativeID: nativeID
        )
    }

    /// Returns the current authorization and catalog-playback access snapshot.
    func currentAccess() async -> MusicProviderAccess {
        await accessSnapshot(for: MusicAuthorization.currentStatus)
    }

    /// Requests Apple Music authorization and returns the resulting access snapshot.
    func requestAccess() async -> MusicProviderAccess {
        let authorizationStatus = await MusicAuthorization.request()
        return await accessSnapshot(for: authorizationStatus)
    }

    /// Begins or continues a catalog search and caches its provider-neutral results.
    func searchPage(
        _ request: SearchPageRequest,
        limit: Int
    ) async throws -> SearchPage {
        switch request {
        case .initial(let query):
            return try await search(query, limit: limit, offset: 0)

        case .continuation(let cursor):
            let appleMusicCursor = try AppleMusicSearchCursor(
                searchCursor: cursor
            )
            return try await search(
                appleMusicCursor.query,
                limit: limit,
                offset: appleMusicCursor.offset
            )
        }
    }

    /// Searches one catalog page and updates the session caches used by playback.
    private func search(
        _ query: String,
        limit: Int,
        offset: Int
    ) async throws -> SearchPage {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = limit
        request.offset = offset
        let response = try await request.response()

        let summaries = response.songs.map { appleMusicSong in
            let nativeID = appleMusicSong.id.rawValue
            let songSummary = SongSummary(
                appleMusicNativeID: nativeID,
                title: appleMusicSong.title,
                artistName: appleMusicSong.artistName,
                artworkURL: appleMusicSong.artwork?.url(width: 300, height: 300),
                duration: appleMusicSong.duration
            )
            songsByNativeID[nativeID] = appleMusicSong
            return songSummary
        }

        let nextCursor: SearchCursor? =
            if response.songs.hasNextBatch {
                try AppleMusicSearchCursor(
                    query: query,
                    offset: offset + summaries.count
                ).searchCursor()
            } else {
                nil
            }

        return SearchPage(
            songs: summaries,
            nextCursor: nextCursor
        )
    }

    /// Replaces the application queue with cached songs and begins at the requested item.
    func replaceQueue(
        itemIDs: [MusicItemID],
        startingItemID: MusicItemID
    ) async throws {
        guard !itemIDs.isEmpty,
            itemIDs.allSatisfy({ $0.providerID == Self.providerID }),
            let startingIndex = itemIDs.firstIndex(of: startingItemID)
        else {
            throw MusicProviderError.unavailable
        }

        var songs: [Song] = []
        songs.reserveCapacity(itemIDs.count)
        for itemID in itemIDs {
            guard let song = songsByNativeID[itemID.nativeID] else {
                throw MusicProviderError.unavailable
            }
            songs.append(song)
        }

        let startingSong = songs[startingIndex]
        try Task.checkCancellation()
        player.queue = ApplicationMusicPlayer.Queue(
            for: songs,
            startingAt: startingSong
        )
        try await player.prepareToPlay()
        try Task.checkCancellation()
        try await player.play()
    }

    /// Resumes the existing application-player queue without replacing its item or position.
    func play() async throws {
        try await player.play()
    }

    /// Requests movement through the active queue when another entry exists.
    ///
    /// - Parameter direction: The provider-relative movement to request.
    /// - Returns: Whether MusicKit accepted a transition or the queue boundary
    ///   prevented one from being requested.
    func navigate(
        _ direction: PlaybackNavigationDirection
    ) async throws -> PlaybackNavigationResult {
        guard currentQueuePosition.canTransition(direction) else {
            return .boundaryReached
        }

        switch direction {
        case .previous:
            try await player.skipToPreviousEntry()
        case .next:
            try await player.skipToNextEntry()
        }
        return .accepted
    }

    /// Resolves the native queue into the boundary information required for transitions.
    private var currentQueuePosition: AppleMusicQueuePosition {
        AppleMusicQueuePosition(
            entryIDs: player.queue.entries.map(\.id),
            currentEntryID: player.queue.currentEntry?.id
        )
    }

    /// Pauses playback while preserving the current position.
    func pause() {
        player.pause()
    }

    /// Stops playback and resets the transport position.
    func stop() {
        player.stop()
        player.playbackTime = 0
    }

    /// Moves playback to a nonnegative position.
    func seek(to time: TimeInterval) {
        player.playbackTime = max(0, time)
    }

    /// Polls the application player and yields provider-neutral playback snapshots.
    func playbackSnapshots() -> AsyncStream<PlaybackSnapshot> {
        AsyncStream { continuation in
            let observationTask = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                while !Task.isCancelled {
                    continuation.yield(await self.playbackSnapshot())
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                observationTask.cancel()
            }
        }
    }

    /// Preserves authorized status with unknown playback eligibility when subscription lookup fails.
    private func accessSnapshot(
        for appleMusicAuthorizationStatus: MusicAuthorization.Status
    ) async -> MusicProviderAccess {
        let authorizationStatus = MusicAuthorizationStatus(
            appleMusicAuthorizationStatus.appleMusicStatus
        )
        guard authorizationStatus == .authorized else {
            return .init(
                authorization: authorizationStatus,
                playbackEligibility: .unknown
            )
        }
        do {
            let subscription = try await MusicSubscription.current
            return .init(
                authorization: .authorized,
                playbackEligibility: CatalogPlaybackEligibility(
                    canPlayCatalogContent: subscription.canPlayCatalogContent
                )
            )
        } catch {
            return .init(
                authorization: .authorized,
                playbackEligibility: .unknown
            )
        }
    }

    /// Reads the player as the transport source of truth and normalizes its state.
    private func playbackSnapshot() -> PlaybackSnapshot {
        let appleMusicStatus: AppleMusicPlaybackStatus
        switch player.state.playbackStatus {
        case .playing, .seekingForward, .seekingBackward:
            appleMusicStatus = .playing
        case .paused:
            appleMusicStatus = .paused
        case .stopped:
            appleMusicStatus = .stopped
        case .interrupted:
            appleMusicStatus = .interrupted
        @unknown default:
            appleMusicStatus = .interrupted
        }

        let currentTime: TimeInterval
        if appleMusicStatus == .stopped {
            currentTime = 0
        } else {
            currentTime = max(0, player.playbackTime)
        }
        return PlaybackSnapshot(
            currentItemID: currentItemID,
            status: PlaybackStatus(appleMusicStatus),
            currentTime: currentTime,
            playbackRate: PlaybackRate(value: player.state.playbackRate),
            repeatMode: PlaybackRepeatMode(player.state.repeatMode),
            shuffleMode: PlaybackShuffleMode(player.state.shuffleMode)
        )
    }
}

extension MusicAuthorization.Status {
    /// Maps unknown future MusicKit authorization statuses conservatively to restricted.
    fileprivate var appleMusicStatus: AppleMusicAuthorizationStatus {
        switch self {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .restricted
        }
    }
}
