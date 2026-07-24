@preconcurrency import AVFoundation

/// Maps one AVPlayer's raw events into Crescendo's playback-observation language.
///
/// The player and registry are shared with the other AVFoundation mechanics, so
/// snapshots and one-time events always reflect the same installed item without
/// this type owning any state of its own.
@MainActor
struct AVPlayerObservation {
    let player: AVPlayer
    let registry: AVPlayerItemRegistry

    /// Creates a playback-observation stream backed by one cancellable subscription.
    ///
    /// Terminating the returned stream removes every AVPlayer registration owned by
    /// that subscription.
    ///
    /// - Returns: A stream of player-confirmed snapshots and one-time item events.
    func observations() -> AsyncStream<PlaybackObservation> {
        AsyncStream { continuation in
            let subscription = AVPlayerObservationSubscription(
                player: player
            ) { [self] event in
                guard let observation = observation(for: event) else { return }
                continuation.yield(observation)
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    subscription.cancel()
                }
            }
        }
    }

    /// Converts a raw AVPlayer event into Crescendo's playback-observation language.
    ///
    /// - Parameter event: The infrastructure event emitted by the active
    ///   subscription.
    /// - Returns: A provider-neutral observation, or `nil` when the event references
    ///   an item that is not registered to this playback implementation.
    private func observation(
        for event: AVPlayerObservationSubscription.Event
    ) -> PlaybackObservation? {
        switch event {
        case .stateChanged:
            return .snapshot(snapshot())

        case .completed(let item):
            guard let trackID = registry.trackID(for: item) else { return nil }
            return .completed(trackID)

        case .failed(let item):
            guard let trackID = registry.trackID(for: item) else { return nil }
            return .failed(trackID, .playbackFailed)
        }
    }

    /// Reads the current player state without introducing application-owned policy.
    ///
    /// The result is `.idle` when no item is installed. Non-finite duration becomes
    /// `nil`, and negative timeline positions are clamped to zero.
    ///
    /// - Returns: The current provider-neutral playback snapshot.
    private func snapshot() -> PlaybackSnapshot {
        guard let item = player.currentItem else { return .idle }
        let durationSeconds = item.duration.seconds
        let duration =
            durationSeconds.isFinite && durationSeconds >= 0
            ? durationSeconds
            : nil
        let status: PlaybackStatus =
            switch player.timeControlStatus {
            case .paused:
                .paused
            case .waitingToPlayAtSpecifiedRate:
                .waiting
            case .playing:
                .playing
            @unknown default:
                .waiting
            }
        return PlaybackSnapshot(
            currentTrackID: registry.trackID(for: item),
            status: status,
            position: max(0, player.currentTime().seconds),
            duration: duration
        )
    }
}
