import Foundation

/// Provides deterministic in-memory music behavior for tests and previews.
actor FakeMusicProvider {
    private let configuredAccess: MusicProviderAccess
    private let configuredResults: [SongSummary]
    private var playbackSnapshot = MusicPlaybackSnapshot.idle

    init(access: MusicProviderAccess, searchResults: [SongSummary]) {
        self.configuredAccess = access
        self.configuredResults = searchResults
    }

    func client() -> MusicProviderClient {
        MusicProviderClient(
            currentAccess: { [weak self] in
                self?.configuredAccess
                    ?? .init(authorization: .denied, playbackEligibility: .unknown)
            },
            requestAccess: { [weak self] in
                self?.configuredAccess
                    ?? .init(authorization: .denied, playbackEligibility: .unknown)
            },
            search: { [weak self] _, limit in
                Array((self?.configuredResults ?? []).prefix(limit))
            },
            play: { [weak self] itemID in
                guard let self else { throw MusicProviderError.unavailable }
                await self.setPlaying(itemID)
            },
            pause: { [weak self] in await self?.setStatus(.paused) },
            stop: { [weak self] in await self?.stopPlayback() },
            seek: { [weak self] time in await self?.setTime(time) },
            playbackSnapshots: { [weak self] in
                let currentSnapshot = await self?.playbackSnapshot ?? .idle
                return AsyncStream { continuation in
                    continuation.yield(currentSnapshot)
                    continuation.finish()
                }
            }
        )
    }

    private func setPlaying(_ itemID: MusicItemID) {
        playbackSnapshot.status = .playing
    }

    private func setStatus(_ status: MusicPlaybackStatus) {
        playbackSnapshot.status = status
    }

    private func stopPlayback() {
        playbackSnapshot = .idle
    }

    private func setTime(_ time: TimeInterval) {
        playbackSnapshot.currentTime = time
    }
}
