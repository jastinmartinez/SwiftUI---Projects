import AVFoundation
import Foundation

/// Prepares validated AVPlayer items without controlling playback.
struct VideoPlayableItemLoader: Sendable {
    var load: @MainActor @Sendable (URL) async throws -> AVPlayerItem
}

extension VideoPlayableItemLoader {
    /// Validates an AVURLAsset before producing its player item.
    static let live = Self { url in
        let asset = AVURLAsset(url: url)
        do {
            guard try await asset.load(.isPlayable) else {
                throw VideoPlaybackError.notPlayable
            }
            return AVPlayerItem(asset: asset)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VideoPlaybackError {
            throw error
        } catch {
            throw VideoPlaybackError.loadFailed
        }
    }
}
