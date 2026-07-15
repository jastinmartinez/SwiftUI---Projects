import MusicKit

/// Owns Apple Music authorization, catalog access, mapping, and session caches.
actor AppleMusicProvider {
    /// The stable application-owned identifier for Apple Music.
    static let providerID: MusicProviderID = "apple-music"

    /// Returns the current authorization and catalog-playback access snapshot.
    func currentAccess() async -> MusicProviderAccess {
        await accessSnapshot(for: MusicAuthorization.currentStatus)
    }

    /// Requests Apple Music authorization and returns the resulting access snapshot.
    func requestAccess() async -> MusicProviderAccess {
        let authorizationStatus = await MusicAuthorization.request()
        return await accessSnapshot(for: authorizationStatus)
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
