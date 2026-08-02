import Foundation

extension Track {
    /// Maps one eligible Audius response row into Crescendo's playable track.
    ///
    /// This is the sole Audius infrastructure-to-domain mapping boundary.
    /// Provider DTOs and Audius eligibility fields cannot cross into features.
    ///
    /// - Parameters:
    ///   - audiusTrack: Provider metadata returned by the Audius search API.
    ///   - playbackURL: Stable Audius stream endpoint for the track identity.
    init?(audiusTrack: AudiusTrack, playbackURL: URL) {
        let nativeID = audiusTrack.id.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            !nativeID.isEmpty,
            audiusTrack.isStreamable,
            !audiusTrack.isStreamGated,
            playbackURL.scheme?.lowercased() == "https"
        else {
            return nil
        }

        let rawArtistName = audiusTrack.user?.name?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let artistName: String?
        if let rawArtistName, !rawArtistName.isEmpty {
            artistName = rawArtistName
        } else {
            artistName = nil
        }

        self.init(
            id: TrackID(providerID: .audius, nativeID: nativeID),
            title: audiusTrack.title,
            artistName: artistName,
            albumTitle: nil,
            artworkURL: audiusTrack.artwork?.url480.flatMap {
                URL(httpString: $0)
            },
            duration: audiusTrack.duration,
            playbackURL: playbackURL
        )
    }
}
