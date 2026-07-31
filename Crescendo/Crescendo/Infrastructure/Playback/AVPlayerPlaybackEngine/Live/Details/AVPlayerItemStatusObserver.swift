@preconcurrency import AVFoundation

/// Registers one AVPlayerItem status callback and returns its owned invalidation.
@MainActor
struct AVPlayerItemStatusObserver {
    /// Cancels one active item-status registration.
    @MainActor
    struct Token {
        private let invalidateRegistration: @MainActor () -> Void

        init(invalidate: @escaping @MainActor () -> Void) {
            invalidateRegistration = invalidate
        }

        /// Stops future callbacks from this status registration.
        func invalidate() {
            invalidateRegistration()
        }
    }

    let observe: @MainActor (
        AVPlayerItem,
        @escaping @MainActor (AVPlayerItem.Status) -> Void
    ) -> Token

    /// The typed KVO observer used by live AVFoundation composition.
    ///
    /// Initial and subsequent values are delivered on the Main Actor so an item
    /// that fails before callback registration completes is not missed.
    static let live = Self { item, receive in
        let observation = item.observe(
            \.status,
            options: [.initial, .new]
        ) { _, change in
            guard let status = change.newValue else { return }
            Task { @MainActor in
                receive(status)
            }
        }
        return Token {
            observation.invalidate()
        }
    }
}
