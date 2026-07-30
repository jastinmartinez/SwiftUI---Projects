extension TrackRowView.Model {
    /// Adapts provider-neutral track metadata into the row presentation contract.
    ///
    /// - Parameters:
    ///   - track: The domain metadata projected into the row.
    ///   - accessory: The trailing affordance appropriate for the owning surface.
    ///   - showsDuration: Whether the owning surface presents catalog duration.
    init(
        _ track: Track,
        accessory: Accessory,
        showsDuration: Bool
    ) {
        self.init(
            id: track.id,
            title: track.title,
            artistName: track.artistName,
            artworkURL: track.artworkURL,
            durationText: showsDuration
                ? track.duration?.musicDurationText
                : nil,
            accessory: accessory
        )
    }
}
