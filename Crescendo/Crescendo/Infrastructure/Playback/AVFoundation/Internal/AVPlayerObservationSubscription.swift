@preconcurrency import AVFoundation
import Foundation

/// Owns the AVPlayer registrations for one playback-observation stream.
@MainActor
final class AVPlayerObservationSubscription {
    private let player: AVPlayer
    private var receive: (@MainActor (Event) -> Void)?
    private var keyValueObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var periodicTimeObserver: Any?
    private var isCancelled = false

    /// Starts every observation required by a playback-observation stream.
    ///
    /// The supplied callback is invoked on the Main Actor and remains active
    /// until ``cancel()`` is called.
    ///
    /// - Parameters:
    ///   - player: The shared player whose state and current item are observed.
    ///   - receive: The callback that receives raw AVFoundation events.
    init(
        player: AVPlayer,
        receive: @escaping @MainActor (Event) -> Void
    ) {
        self.player = player
        self.receive = receive

        registerKeyValueObservations()
        registerPeriodicTimeObserver()
        registerNotificationObservers()
    }

    /// Removes every registration and prevents subsequent event delivery.
    ///
    /// Calling this method more than once has no additional effect.
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        receive = nil
        for observation in keyValueObservations { observation.invalidate() }
        keyValueObservations.removeAll()
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        notificationTokens.removeAll()
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
    }

    /// Observes current-item and transport-state changes.
    ///
    /// Current-item observation includes the initial value so a new stream
    /// receives player state without waiting for the next mutation.
    private func registerKeyValueObservations() {
        keyValueObservations = [
            player.observe(\.currentItem, options: [.initial, .new]) {
                [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.send(.stateChanged)
                }
            },
            player.observe(\.timeControlStatus, options: [.new]) {
                [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.send(.stateChanged)
                }
            },
        ]
    }

    /// Emits state-change events while the current item's timeline advances.
    ///
    /// The returned AVPlayer token is retained until ``cancel()`` removes it.
    private func registerPeriodicTimeObserver() {
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.send(.stateChanged)
            }
        }
    }

    /// Observes one-time completion and failure events for player items.
    ///
    /// NotificationCenter delivery is process-wide. The subscription forwards
    /// the item identity, and `AVPlayerObservation` later rejects items that are
    /// absent from its registry.
    private func registerNotificationObservers() {
        let completed = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor [weak self] in
                self?.send(.completed(item))
            }
        }

        let failed = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor [weak self] in
                self?.send(.failed(item))
            }
        }

        notificationTokens = [completed, failed]
    }

    /// Delivers an event only while the subscription remains active.
    ///
    /// - Parameter event: The raw AVFoundation event to forward.
    private func send(_ event: Event) {
        guard !isCancelled else { return }
        receive?(event)
    }
}

extension AVPlayerObservationSubscription {
    /// A raw AVFoundation event that never crosses the infrastructure boundary.
    enum Event {
        /// Player identity, transport state, or timeline values may have changed.
        case stateChanged

        /// The supplied player item reached its end.
        case completed(AVPlayerItem)

        /// The supplied player item failed during playback.
        case failed(AVPlayerItem)
    }
}
