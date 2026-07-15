import Foundation

struct SongSummary: Equatable, Identifiable, Sendable {
    let id: MusicItemID
    let title: String
    let artistName: String
    let artworkURL: URL?
}
