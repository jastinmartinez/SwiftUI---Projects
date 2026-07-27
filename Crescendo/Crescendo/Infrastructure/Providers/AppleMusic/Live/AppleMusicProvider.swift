import Foundation
@preconcurrency import MusicKit

/// Owns Apple Music authorization, catalog search, and provider mapping.
actor AppleMusicProvider {
    /// The stable application-owned identifier for Apple Music.
    static let providerID: ProviderID = .appleMusic

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

    /// Searches one catalog page and maps its tracks into application-owned values.
    private func search(
        _ query: String,
        limit: Int,
        offset: Int
    ) async throws -> SearchPage {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = limit
        request.offset = offset
        let response = try await request.response()

        let tracks = response.songs.map { appleMusicSong in
            let nativeID = appleMusicSong.id.rawValue
            let track = Track(
                appleMusicNativeID: nativeID,
                title: appleMusicSong.title,
                artistName: appleMusicSong.artistName,
                albumTitle: appleMusicSong.albumTitle,
                artworkURL: appleMusicSong.artwork?.url(width: 300, height: 300),
                duration: appleMusicSong.duration
            )
            return track
        }

        let nextCursor: SearchCursor? =
            if response.songs.hasNextBatch {
                try AppleMusicSearchCursor(
                    query: query,
                    offset: offset + tracks.count
                ).searchCursor()
            } else {
                nil
            }

        return SearchPage(
            tracks: tracks,
            nextCursor: nextCursor
        )
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
