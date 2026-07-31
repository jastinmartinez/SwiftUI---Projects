import Foundation

@testable import Crescendo

extension Track {
    init(
        id: TrackID,
        title: String,
        artistName: String?,
        albumTitle: String?,
        artworkURL: URL?,
        duration: TimeInterval?
    ) {
        self.init(
            id: id,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            artworkURL: artworkURL,
            duration: duration,
            playbackURL: URL(
                fileURLWithPath:
                    "/tmp/\(id.providerID.rawValue)-\(id.nativeID).m4a"
            )
        )
    }
}
