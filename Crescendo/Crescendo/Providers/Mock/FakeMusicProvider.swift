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
            search: { [weak self] _, limit in
                Array((self?.configuredResults ?? []).prefix(limit))
            }
        )
    }

    func playbackControlClient() -> PlaybackControlClient {
        PlaybackControlClient(
            play: { [weak self] _ in
                guard let self else { throw MusicProviderError.unavailable }
                await self.startPlayback()
            },
            resume: { [weak self] in await self?.setStatus(.playing) },
            pause: { [weak self] in await self?.setStatus(.paused) },
            stop: { [weak self] in await self?.stopPlayback() },
            seek: { [weak self] time in await self?.setTime(time) }
        )
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

    private func startPlayback() {
        playbackSnapshot.status = .playing
        playbackSnapshot.currentTime = 0
    }

    private func setStatus(_ status: MusicPlaybackStatus) {
        playbackSnapshot.status = status
    }

    private func stopPlayback() {
        playbackSnapshot.status = .stopped
        playbackSnapshot.currentTime = 0
    }

    private func setTime(_ time: TimeInterval) {
        playbackSnapshot.currentTime = time
    }
}
