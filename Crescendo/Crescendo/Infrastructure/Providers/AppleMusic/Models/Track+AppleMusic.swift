import Foundation

extension Track {
    /// Creates app-owned track metadata with an Apple Music-namespaced identity.
    init(
        appleMusicNativeID: String,
        title: String,
        artistName: String,
        albumTitle: String?,
        artworkURL: URL?,
        duration: TimeInterval?
    ) {
        self.init(
            id: TrackID(
                providerID: .appleMusic,
                nativeID: appleMusicNativeID
            ),
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            artworkURL: artworkURL,
            duration: duration
        )
    }
}
