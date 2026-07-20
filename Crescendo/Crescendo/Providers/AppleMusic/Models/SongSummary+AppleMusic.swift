import Foundation

extension SongSummary {
    /// Creates app-owned song metadata with an Apple Music-namespaced identity.
    init(
        appleMusicNativeID: String,
        title: String,
        artistName: String,
        artworkURL: URL?,
        duration: TimeInterval?
    ) {
        self.init(
            id: .init(
                providerID: .appleMusic,
                nativeID: appleMusicNativeID
            ),
            title: title,
            artistName: artistName,
            artworkURL: artworkURL,
            duration: duration
        )
    }
}
