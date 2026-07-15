import MusicKit

/// Owns Apple Music authorization, catalog access, mapping, and session caches.
actor AppleMusicProvider {
    /// The stable application-owned identifier for Apple Music.
    static let providerID: MusicProviderID = "apple-music"

    private var songsByNativeID: [String: Song] = [:]
    private var summariesByNativeID: [String: SongSummary] = [:]

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
            let songSummary = AppleMusicSongMetadata(
                nativeID: nativeID,
                title: appleMusicSong.title,
                artistName: appleMusicSong.artistName,
                artworkURL: appleMusicSong.artwork?.url(width: 300, height: 300)
            ).songSummary
            songsByNativeID[nativeID] = appleMusicSong
            summariesByNativeID[nativeID] = songSummary
            return songSummary
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
