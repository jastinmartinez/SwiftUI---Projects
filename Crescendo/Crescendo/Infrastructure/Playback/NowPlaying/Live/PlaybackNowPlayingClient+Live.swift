@preconcurrency import MediaPlayer
@preconcurrency import UIKit

extension PlaybackNowPlayingClient {
    /// Creates the production client that publishes confirmed playback to one
    /// explicitly supplied system information center.
    ///
    /// The client owns the Main Actor hop required by MediaPlayer and one
    /// replaceable best-effort image task. Text and timing publish before image
    /// loading begins. It does not inspect playback state or decide
    /// when presentation should be updated.
    ///
    /// - Parameters:
    ///   - infoCenter: The system publication destination owned by the
    ///     application composition root.
    ///   - image: Loads optional image bytes outside reducer state.
    /// - Returns: Provider-neutral publication operations backed by MediaPlayer.
    @MainActor
    static func live(
        infoCenter: MPNowPlayingInfoCenter,
        image: NowPlayingImageClient
    ) -> Self {
        let publication = Publication(
            infoCenter: infoCenter,
            image: image
        )
        return Self(
            publish: { projection in
                await publication.publish(projection)
            },
            clear: {
                await publication.clear()
            }
        )
    }
}

private extension PlaybackNowPlayingClient {
    /// Coordinates replaceable image work with the current system metadata.
    ///
    /// This state belongs to the live MediaPlayer boundary. Reducers publish
    /// immutable projections and never observe image loading or decoding.
    @MainActor
    final class Publication {
        private let infoCenter: MPNowPlayingInfoCenter
        private let image: NowPlayingImageClient
        private var artworkTask: Task<Void, Never>?
        private var currentTrackID: TrackID?

        init(
            infoCenter: MPNowPlayingInfoCenter,
            image: NowPlayingImageClient
        ) {
            self.infoCenter = infoCenter
            self.image = image
        }

        func publish(_ projection: Projection) {
            artworkTask?.cancel()
            currentTrackID = projection.item.id
            infoCenter.nowPlayingInfo = projection.mediaPlayerInfo

            guard let artworkURL = projection.item.artworkURL else {
                artworkTask = nil
                return
            }

            let trackID = projection.item.id
            let image = image
            artworkTask = Task { @MainActor [weak self] in
                guard let data = try? await image.load(artworkURL) else {
                    return
                }
                guard let decodedImage = await self?.decodeImage(data) else {
                    return
                }
                self?.publishArtwork(decodedImage, matching: trackID)
            }
        }

        private nonisolated func decodeImage(
            _ data: Data
        ) async -> UIImage? {
            await Task.detached(priority: .utility) {
                UIImage(data: data)
            }.value
        }

        private func publishArtwork(
            _ image: UIImage,
            matching trackID: TrackID
        ) {
            guard currentTrackID == trackID else { return }
            guard var info = infoCenter.nowPlayingInfo else { return }

            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: image.size,
                requestHandler: { _ in image }
            )
            infoCenter.nowPlayingInfo = info
        }

        func clear() {
            artworkTask?.cancel()
            artworkTask = nil
            currentTrackID = nil
            infoCenter.nowPlayingInfo = nil
        }
    }
}
