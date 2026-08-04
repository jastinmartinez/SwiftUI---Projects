@preconcurrency import AVFoundation

/// Observes whether one AVPlayerItem currently exposes a positive seekable range.
@MainActor
struct AVPlayerItemSeekabilityObserver {
    let observe: @MainActor (AVPlayerItem, @escaping @MainActor (Bool) -> Void) -> Token
}

extension AVPlayerItemSeekabilityObserver {
    @MainActor
    struct Token {
        private let invalidateRegistration: @MainActor () -> Void

        /// Creates a token around the concrete observation invalidation.
        ///
        /// - Parameter invalidate: The action that removes the owned
        ///   AVFoundation registration.
        init(invalidate: @escaping @MainActor () -> Void) {
            invalidateRegistration = invalidate
        }

        /// Invalidates the owned seekability observation.
        func invalidate() {
            invalidateRegistration()
        }
    }
}

extension AVPlayerItemSeekabilityObserver {
    static let live = Self { item, receive in
        let observation = item.observe(
            \.seekableTimeRanges,
            options: [.initial, .new]
        ) { _, change in
            let ranges = change.newValue ?? []
            let isSeekable = ranges.contains { value in
                let seconds = value.timeRangeValue.duration.seconds
                return seconds.isFinite && seconds > 0
            }
            Task { @MainActor in
                receive(isSeekable)
            }
        }
        return Token {
            observation.invalidate()
        }
    }
}
