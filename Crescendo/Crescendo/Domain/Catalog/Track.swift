import Foundation

/// A provider-neutral, playable track retained by Search and Playback.
struct Track: Equatable, Identifiable, Sendable {
    let id: TrackID
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let duration: TimeInterval?
    let playbackURL: URL
}
