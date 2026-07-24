@preconcurrency import AVFoundation

@MainActor
struct AVPlayerItemPreparer {
    let loadIsPlayable: (AVURLAsset) async throws -> Bool

    /// Validates a resolved resource before creating its player item.
    ///
    /// - Parameter resource: The provider-resolved location to inspect.
    /// - Returns: An item whose asset reported that it is playable.
    /// - Throws: `PlaybackFailure.preparationFailed` when loading fails, or
    ///   `PlaybackFailure.unsupportedResource` when the asset is not playable.
    func prepare(_ resource: PlaybackResource) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: resource.location.url)
        do {
            guard try await loadIsPlayable(asset) else {
                throw PlaybackFailure.unsupportedResource
            }
            return AVPlayerItem(asset: asset)
        } catch let failure as PlaybackFailure {
            throw failure
        } catch {
            throw PlaybackFailure.preparationFailed
        }
    }
}

extension AVPlayerItemPreparer {
    static func live() -> Self {
        Self(
            loadIsPlayable: { asset in
                try await asset.load(.isPlayable)
            }
        )
    }
}
