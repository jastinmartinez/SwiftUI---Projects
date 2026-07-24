import Foundation

/// Provides deterministic in-memory music behavior for tests and previews.
actor FakeMusicProvider {
    private struct SearchOffset: Codable {
        let value: Int
    }

    private let configuredAccess: MusicProviderAccess
    private let configuredResults: [Track]
    private var playbackSnapshot = PlaybackSnapshot.idle
    private var queueItemIDs: [TrackID] = []
    private var queueCurrentIndex: Int?

    init(access: MusicProviderAccess, searchResults: [Track]) {
        self.configuredAccess = access
        self.configuredResults = searchResults
    }

    func accessClient() -> ProviderAccessClient {
        ProviderAccessClient(
            currentAccess: { [weak self] _ in
                self?.configuredAccess
                    ?? .init(authorization: .denied, playbackEligibility: .unknown)
            },
            requestAccess: { [weak self] _ in
                self?.configuredAccess
                    ?? .init(authorization: .denied, playbackEligibility: .unknown)
            }
        )
    }

    func searchClient() -> ProviderSearchClient {
        ProviderSearchClient(
            searchPage: { [weak self] _, request, limit in
                guard let self else { throw MusicProviderError.unavailable }
                let offset: Int
                switch request {
                case .initial:
                    offset = 0
                case .continuation(let cursor):
                    offset = try JSONDecoder().decode(
                        SearchOffset.self,
                        from: Data(cursor.value.utf8)
                    ).value
                }
                return await self.searchPage(
                    offset: offset,
                    limit: limit
                )
            }
        )
    }

    func playbackTransportClient() -> PlaybackTransportClient {
        PlaybackTransportClient(
            play: { [weak self] in
                guard let self else { throw MusicProviderError.unavailable }
                await self.setStatus(.playing)
            },
            pause: { [weak self] in
                guard let self else { throw MusicProviderError.unavailable }
                await self.setStatus(.paused)
            }
        )
    }

    func playbackTimelineClient() -> PlaybackTimelineClient {
        PlaybackTimelineClient(
            seek: { [weak self] time in
                guard let self else { throw MusicProviderError.unavailable }
                await self.setTime(time)
            }
        )
    }

    func playbackQueueClient() -> PlaybackQueueClient {
        PlaybackQueueClient(
            replace: { [weak self] itemIDs, startingItemID in
                guard let self else { throw MusicProviderError.unavailable }
                try await self.replaceQueue(
                    itemIDs: itemIDs,
                    startingItemID: startingItemID
                )
            },
            navigate: { [weak self] direction in
                guard let self else { throw MusicProviderError.unavailable }
                return try await self.moveCurrentItem(
                    by: direction == .previous ? -1 : 1
                )
            },
            setRepeat: { [weak self] mode in
                guard let self else { throw MusicProviderError.unavailable }
                await self.setRepeat(mode)
            },
            setShuffle: { [weak self] mode in
                guard let self else { throw MusicProviderError.unavailable }
                await self.setShuffle(mode)
            }
        )
    }

    func queuedItemIDs() -> [TrackID] {
        queueItemIDs
    }

    func playbackObservationClient() -> PlaybackObservationClient {
        PlaybackObservationClient(
            observations: { [weak self] in
                let currentSnapshot = await self?.playbackSnapshot ?? .idle
                return AsyncStream { continuation in
                    continuation.yield(.snapshot(currentSnapshot))
                    continuation.finish()
                }
            }
        )
    }

    private func replaceQueue(
        itemIDs: [TrackID],
        startingItemID: TrackID
    ) throws {
        let cachedItemIDs = Set(configuredResults.map(\.id))
        guard !itemIDs.isEmpty,
            itemIDs.allSatisfy({ $0.providerID == startingItemID.providerID }),
            itemIDs.allSatisfy(cachedItemIDs.contains),
            let startingIndex = itemIDs.firstIndex(of: startingItemID)
        else {
            throw MusicProviderError.unavailable
        }

        queueItemIDs = itemIDs
        queueCurrentIndex = startingIndex
        playbackSnapshot = PlaybackSnapshot(
            currentTrackID: itemIDs[startingIndex],
            status: .playing,
            position: 0,
            duration: nil
        )
    }

    private func moveCurrentItem(
        by offset: Int
    ) throws -> PlaybackQueueNavigationResult {
        guard let queueCurrentIndex else {
            throw MusicProviderError.unavailable
        }
        let destinationIndex = queueCurrentIndex + offset
        guard queueItemIDs.indices.contains(destinationIndex) else {
            return .boundaryReached
        }

        self.queueCurrentIndex = destinationIndex
        playbackSnapshot = PlaybackSnapshot(
            currentTrackID: queueItemIDs[destinationIndex],
            status: playbackSnapshot.status,
            position: 0,
            duration: nil
        )
        return .accepted
    }

    /// Repeat mode is confirmed via the queue command response, not the player snapshot.
    private func setRepeat(_ mode: PlaybackRepeatMode) {}

    /// Shuffle mode is confirmed via the queue command response, not the player snapshot.
    private func setShuffle(_ mode: PlaybackShuffleMode) {}

    private func searchPage(offset: Int, limit: Int) -> SearchPage {
        let tracks = Array(
            configuredResults.dropFirst(offset).prefix(limit)
        )
        let nextOffset = offset + tracks.count
        let nextCursor: SearchCursor?
        if nextOffset < configuredResults.count,
            let data = try? JSONEncoder().encode(
                SearchOffset(value: nextOffset)
            ),
            let value = String(data: data, encoding: .utf8)
        {
            nextCursor = SearchCursor(value: value)
        } else {
            nextCursor = nil
        }
        return SearchPage(tracks: tracks, nextCursor: nextCursor)
    }

    private func setStatus(_ status: PlaybackStatus) {
        playbackSnapshot = PlaybackSnapshot(
            currentTrackID: playbackSnapshot.currentTrackID,
            status: status,
            position: playbackSnapshot.position,
            duration: playbackSnapshot.duration
        )
    }

    private func setTime(_ time: TimeInterval) {
        playbackSnapshot = PlaybackSnapshot(
            currentTrackID: playbackSnapshot.currentTrackID,
            status: playbackSnapshot.status,
            position: time,
            duration: playbackSnapshot.duration
        )
    }
}
