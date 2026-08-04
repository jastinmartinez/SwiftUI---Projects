@preconcurrency import AVFoundation

@MainActor
struct AVPlayerItemPreparer {
    let loadIsPlayable: (AVURLAsset) async throws -> Bool
    let makeItem: (AVURLAsset) -> AVPlayerItem

    /// Validates a playback URL before creating its player item with the
    /// configured item factory.
    ///
    /// - Parameter playbackURL: The playable location to inspect.
    /// - Returns: An item whose asset reported that it is playable.
    /// - Throws: `PlaybackFailure.preparationFailed` when loading fails, or
    ///   `PlaybackFailure.unsupportedResource` when the asset is not playable.
    func prepare(_ playbackURL: URL) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: playbackURL)
        do {
            guard try await loadIsPlayable(asset) else {
                throw PlaybackFailure.unsupportedResource
            }
            return makeItem(asset)
        } catch let failure as PlaybackFailure {
            throw failure
        } catch {
            throw PlaybackFailure.preparationFailed
        }
    }
}

extension AVPlayerItemPreparer {
    /// Creates the production preparer backed by AVFoundation asset loading and
    /// player-item creation.
    ///
    /// Item creation is injected explicitly so tests can use deterministic
    /// in-memory items without loading network resources. Installation remains
    /// the separate responsibility of `AVPlayerItemInstaller`.
    ///
    /// - Returns: A preparer backed by AVFoundation playability loading and
    ///   player-item creation.
    static func live() -> Self {
        Self(
            loadIsPlayable: { asset in
                try await asset.load(.isPlayable)
            },
            makeItem: { asset in
                AVPlayerItem(asset: asset)
            }
        )
    }
}
