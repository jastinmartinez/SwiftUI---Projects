import Foundation

/// Provides deterministic in-memory music behavior for tests and previews.
actor FakeMusicProvider {
    private struct SearchOffset: Codable {
        let value: Int
    }

    private let configuredAccess: MusicProviderAccess
    private let configuredResults: [SongSummary]
    private var playbackSnapshot = PlaybackSnapshot.idle
    private var queueItemIDs: [MusicItemID] = []
    private var queueCurrentIndex: Int?

    init(access: MusicProviderAccess, searchResults: [SongSummary]) {
        self.configuredAccess = access
        self.configuredResults = searchResults
    }

    func accessClient() -> ProviderAccessClient {
        ProviderAccessClient(
            currentAccess: { [weak self] in
                self?.configuredAccess
                    ?? .init(authorization: .denied, playbackEligibility: .unknown)
            },
            requestAccess: { [weak self] in
                self?.configuredAccess
                    ?? .init(authorization: .denied, playbackEligibility: .unknown)
            }
        )
    }

    func searchClient() -> ProviderSearchClient {
        ProviderSearchClient(
            searchPage: { [weak self] request, limit in
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
            },
            stop: { [weak self] in
                guard let self else { throw MusicProviderError.unavailable }
                await self.stopPlayback()
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
            previous: { [weak self] in
                guard let self else { throw MusicProviderError.unavailable }
                try await self.moveCurrentItem(by: -1)
            },
            next: { [weak self] in
                guard let self else { throw MusicProviderError.unavailable }
                try await self.moveCurrentItem(by: 1)
            }
        )
    }

    func queuedItemIDs() -> [MusicItemID] {
        queueItemIDs
    }

    func playbackObservationClient() -> PlaybackObservationClient {
        PlaybackObservationClient(
            playbackSnapshots: { [weak self] in
                let currentSnapshot = await self?.playbackSnapshot ?? .idle
                return AsyncStream { continuation in
                    continuation.yield(currentSnapshot)
                    continuation.finish()
                }
            }
        )
    }

    private func replaceQueue(
        itemIDs: [MusicItemID],
        startingItemID: MusicItemID
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
            currentItemID: itemIDs[startingIndex],
            status: .playing,
            currentTime: 0,
            playbackRate: .normal,
            repeatMode: .off,
            shuffleMode: .off
        )
    }

    private func moveCurrentItem(by offset: Int) throws {
        guard let queueCurrentIndex else {
            throw MusicProviderError.unavailable
        }
        let destinationIndex = queueCurrentIndex + offset
        guard queueItemIDs.indices.contains(destinationIndex) else {
            throw MusicProviderError.unavailable
        }

        self.queueCurrentIndex = destinationIndex
        playbackSnapshot = PlaybackSnapshot(
            currentItemID: queueItemIDs[destinationIndex],
            status: playbackSnapshot.status,
            currentTime: 0,
            playbackRate: playbackSnapshot.playbackRate,
            repeatMode: playbackSnapshot.repeatMode,
            shuffleMode: playbackSnapshot.shuffleMode
        )
    }

    private func searchPage(offset: Int, limit: Int) -> SearchPage {
        let songs = Array(
            configuredResults.dropFirst(offset).prefix(limit)
        )
        let nextOffset = offset + songs.count
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
        return SearchPage(songs: songs, nextCursor: nextCursor)
    }

    private func setStatus(_ status: PlaybackStatus) {
        playbackSnapshot = PlaybackSnapshot(
            currentItemID: playbackSnapshot.currentItemID,
            status: status,
            currentTime: playbackSnapshot.currentTime,
            playbackRate: playbackSnapshot.playbackRate,
            repeatMode: playbackSnapshot.repeatMode,
            shuffleMode: playbackSnapshot.shuffleMode
        )
    }

    private func stopPlayback() {
        playbackSnapshot = PlaybackSnapshot(
            currentItemID: playbackSnapshot.currentItemID,
            status: .stopped,
            currentTime: 0,
            playbackRate: playbackSnapshot.playbackRate,
            repeatMode: playbackSnapshot.repeatMode,
            shuffleMode: playbackSnapshot.shuffleMode
        )
    }

    private func setTime(_ time: TimeInterval) {
        playbackSnapshot = PlaybackSnapshot(
            currentItemID: playbackSnapshot.currentItemID,
            status: playbackSnapshot.status,
            currentTime: time,
            playbackRate: playbackSnapshot.playbackRate,
            repeatMode: playbackSnapshot.repeatMode,
            shuffleMode: playbackSnapshot.shuffleMode
        )
    }
}
