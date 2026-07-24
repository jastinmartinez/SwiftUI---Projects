extension PlaybackTransportClient {
    static func live(_ transport: AVPlayerTransport) -> Self {
        Self(
            play: { await transport.play() },
            pause: { await transport.pause() }
        )
    }
}
