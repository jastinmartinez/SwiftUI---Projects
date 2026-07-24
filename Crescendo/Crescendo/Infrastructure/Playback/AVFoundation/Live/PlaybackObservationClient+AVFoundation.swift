extension PlaybackObservationClient {
    static func live(_ observation: AVPlayerObservation) -> Self {
        Self(
            observations: { await observation.observations() }
        )
    }
}
