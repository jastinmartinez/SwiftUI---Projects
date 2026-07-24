extension PlaybackTimelineClient {
    static func live(_ timeline: AVPlayerTimeline) -> Self {
        Self(
            seek: { await timeline.seek(to: $0) }
        )
    }
}
