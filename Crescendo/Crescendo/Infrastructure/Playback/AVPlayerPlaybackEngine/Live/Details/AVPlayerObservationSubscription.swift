@preconcurrency import AVFoundation
import Foundation

/// Owns the AVPlayer registrations for one playback-observation stream.
@MainActor
final class AVPlayerObservationSubscription {
    private let player: AVPlayer
    private let itemStatusObserver: AVPlayerItemStatusObserver
    private let itemSeekabilityObserver: AVPlayerItemSeekabilityObserver
    private var receive: (@MainActor (Event) -> Void)?
    private var keyValueObservations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var periodicTimeObserver: Any?
    private var activeItem: AVPlayerItem?
    private var activeItemStatusObservation: AVPlayerItemStatusObserver.Token?
    private var activeItemSeekabilityObservation: AVPlayerItemSeekabilityObserver.Token?
    private var activeItemIsSeekable = false
    private var didEmitActiveItemFailure = false
    private var isCancelled = false

    /// Starts every observation required by a playback-observation stream.
    ///
    /// The supplied callback is invoked on the Main Actor and remains active
    /// until ``cancel()`` is called.
    ///
    /// - Parameters:
    ///   - player: The shared player whose state and current item are observed.
    ///   - itemStatusObserver: The mechanism that registers active-item status
    ///     callbacks and returns their owned invalidation.
    ///   - itemSeekabilityObserver: The mechanism that registers active-item
    ///     seekability callbacks and returns their owned invalidation.
    ///   - receive: The callback that receives raw AVFoundation events.
    init(
        player: AVPlayer,
        itemStatusObserver: AVPlayerItemStatusObserver,
        itemSeekabilityObserver: AVPlayerItemSeekabilityObserver,
        receive: @escaping @MainActor (Event) -> Void
    ) {
        self.player = player
        self.itemStatusObserver = itemStatusObserver
        self.itemSeekabilityObserver = itemSeekabilityObserver
        self.receive = receive

        replaceActiveItemObservations(with: player.currentItem)
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
        activeItemStatusObservation?.invalidate()
        activeItemStatusObservation = nil
        activeItemSeekabilityObservation?.invalidate()
        activeItemSeekabilityObservation = nil
        activeItemIsSeekable = false
        activeItem = nil
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
                [weak self] _, change in
                let item = change.newValue ?? nil
                DispatchQueue.main.async { @MainActor [weak self, item] in
                    self?.replaceActiveItemObservations(with: item)
                    self?.sendStateChanged()
                }
            },
            player.observe(\.timeControlStatus, options: [.new]) {
                [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.sendStateChanged()
                }
            },
        ]
    }

    /// Replaces item observations whenever the player's active item changes.
    ///
    /// Previous status and seekability tokens are invalidated before the new item
    /// is observed. Seekability resets while no player-confirmed range exists.
    ///
    /// - Parameter item: The item identity captured by the current-item KVO
    ///   transition, including transient items that are replaced before the
    ///   Main Actor handles the callback.
    private func replaceActiveItemObservations(
        with item: AVPlayerItem?
    ) {
        guard !isCancelled else { return }
        guard activeItem !== item else { return }

        activeItemStatusObservation?.invalidate()
        activeItemStatusObservation = nil
        activeItemSeekabilityObservation?.invalidate()
        activeItemSeekabilityObservation = nil
        activeItem = item
        activeItemIsSeekable = false
        didEmitActiveItemFailure = false

        guard let item else { return }
        activeItemStatusObservation = itemStatusObserver.observe(item) {
            [weak self, weak item] status in
            guard
                status == .failed,
                let self,
                let item
            else { return }
            self.sendFailureOnce(for: item)
        }
        activeItemSeekabilityObservation = itemSeekabilityObserver.observe(item) {
            [weak self, weak item] isSeekable in
            guard
                let self,
                let item,
                self.activeItem === item,
                self.player.currentItem === item
            else { return }
            self.activeItemIsSeekable = isSeekable
            self.sendStateChanged()
        }
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
                self?.sendStateChanged()
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
                self?.sendFailureOnce(for: item)
            }
        }

        notificationTokens = [completed, failed]
    }

    /// Emits at most one failure for the active item's current installed lifetime.
    ///
    /// - Parameter item: The player item whose terminal failure was observed.
    private func sendFailureOnce(for item: AVPlayerItem) {
        guard
            activeItem === item,
            player.currentItem === item,
            !didEmitActiveItemFailure
        else { return }
        didEmitActiveItemFailure = true
        send(.failed(item))
    }

    /// Suppresses state events during an unprocessed item replacement.
    ///
    /// Seekability callbacks reject stale items before mutating their cached
    /// value. This final check protects every other state-event source.
    private func sendStateChanged() {
        guard activeItem === player.currentItem else { return }
        send(.stateChanged(isSeekable: activeItemIsSeekable))
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
        case stateChanged(isSeekable: Bool)

        /// The supplied player item reached its end.
        case completed(AVPlayerItem)

        /// The supplied player item failed during playback.
        case failed(AVPlayerItem)
    }
}
