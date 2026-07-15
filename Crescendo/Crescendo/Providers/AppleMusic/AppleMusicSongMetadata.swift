import Foundation

/// Maps the shared subset of Apple Music song metadata into the app domain.
struct AppleMusicSongMetadata: Equatable {
    let nativeID: String
    let title: String
    let artistName: String
    let artworkURL: URL?

    /// Returns app-owned song metadata with an Apple Music-namespaced identity.
    var songSummary: SongSummary {
        SongSummary(
            id: .init(
                providerID: AppleMusicProvider.providerID,
                nativeID: nativeID
            ),
            title: title,
            artistName: artistName,
            artworkURL: artworkURL
        )
    }
}
