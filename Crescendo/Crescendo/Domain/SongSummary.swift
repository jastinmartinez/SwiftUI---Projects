import Foundation

/// Shared song metadata that can be supplied by every supported provider.
struct SongSummary: Equatable, Identifiable, Sendable {
    let id: MusicItemID
    let title: String
    let artistName: String
    let artworkURL: URL?
    let duration: TimeInterval?
}
