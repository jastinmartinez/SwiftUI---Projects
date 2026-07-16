import Foundation
@preconcurrency import MusicKit

/// Owns Apple Music authorization, catalog access, playback, mapping, and session caches.
actor AppleMusicProvider {
    /// The stable application-owned identifier for Apple Music.
    static let providerID: MusicProviderID = "apple-music"

    private let player = ApplicationMusicPlayer.shared
    private var songsByNativeID: [String: Song] = [:]
    private var summariesByNativeID: [String: SongSummary] = [:]
    private var selectedSongSummary: SongSummary?

    /// Returns the current authorization and catalog-playback access snapshot.
    func currentAccess() async -> MusicProviderAccess {
        await accessSnapshot(for: MusicAuthorization.currentStatus)
    }

    /// Requests Apple Music authorization and returns the resulting access snapshot.
    func requestAccess() async -> MusicProviderAccess {
        let authorizationStatus = await MusicAuthorization.request()
        return await accessSnapshot(for: authorizationStatus)
    }

    /// Searches at most twenty catalog songs and caches native and app-owned values for this session.
    func search(_ query: String, limit: Int) async throws -> [SongSummary] {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = min(limit, 20)
        let response = try await request.response()

        return response.songs.map { appleMusicSong in
            let nativeID = appleMusicSong.id.rawValue
            let songSummary = SongSummary(
                appleMusicNativeID: nativeID,
                title: appleMusicSong.title,
                artistName: appleMusicSong.artistName,
                artworkURL: appleMusicSong.artwork?.url(width: 300, height: 300)
            )
            songsByNativeID[nativeID] = appleMusicSong
            summariesByNativeID[nativeID] = songSummary
            return songSummary
        }
    }

    /// Replaces the application queue with one cached song, prepares it, and begins playback.
    func play(_ itemID: MusicItemID) async throws {
        guard itemID.providerID == Self.providerID else {
            throw MusicProviderError.unavailable
        }
        guard let song = songsByNativeID[itemID.nativeID] else {
            throw MusicProviderError.unavailable
        }
        guard let songSummary = summariesByNativeID[itemID.nativeID] else {
            throw MusicProviderError.unavailable
        }

        selectedSongSummary = songSummary
        player.queue = [song]
        try await player.prepareToPlay()
        try await player.play()
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
    func playbackSnapshots() -> AsyncStream<MusicPlaybackSnapshot> {
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
        for authorizationStatus: MusicAuthorization.Status
    ) async -> MusicProviderAccess {
        let authorization = MusicAuthorizationState(
            authorizationStatus.appleMusicState
        )
        guard authorization == .authorized else {
            return .init(
                authorization: authorization,
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
    private func playbackSnapshot() -> MusicPlaybackSnapshot {
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
        return MusicPlaybackSnapshot(
            currentItem: selectedSongSummary,
            status: MusicTransportStatus(appleMusicStatus),
            currentTime: currentTime,
            error: nil
        )
    }
}

extension SongSummary {
    /// Creates app-owned song metadata with an Apple Music-namespaced identity.
    init(
        appleMusicNativeID: String,
        title: String,
        artistName: String,
        artworkURL: URL?
    ) {
        self.init(
            id: .init(
                providerID: AppleMusicProvider.providerID,
                nativeID: appleMusicNativeID
            ),
            title: title,
            artistName: artistName,
            artworkURL: artworkURL
        )
    }
}

extension MusicAuthorization.Status {
    /// Maps unknown future MusicKit authorization statuses conservatively to restricted.
    fileprivate var appleMusicState: AppleMusicAuthorizationState {
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
