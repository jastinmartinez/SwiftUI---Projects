import Foundation

enum MusicTransportStatus: Equatable, Sendable {
  case idle
  case loading
  case playing
  case paused
  case stopped
  case failed
}

struct MusicPlaybackSnapshot: Equatable, Sendable {
  var currentItem: SongSummary?
  var status: MusicTransportStatus
  var currentTime: TimeInterval
  var error: MusicProviderError?

  static let idle = Self(
    currentItem: nil,
    status: .idle,
    currentTime: 0,
    error: nil
  )
}
