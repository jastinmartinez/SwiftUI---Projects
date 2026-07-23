import Foundation

/// Metadata shared by every Phase 1 music provider.
struct Track: Equatable, Identifiable, Sendable {
    let id: TrackID
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let duration: TimeInterval?
}
