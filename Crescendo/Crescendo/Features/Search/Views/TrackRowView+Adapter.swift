extension TrackRowView.Model {
    /// Adapts provider-neutral track metadata into the row presentation contract.
    ///
    /// - Parameters:
    ///   - track: The domain metadata projected into the row.
    ///   - accessory: The trailing affordance appropriate for the owning surface.
    init(
        _ track: Track,
        accessory: Accessory
    ) {
        self.init(
            id: track.id,
            title: track.title,
            artistName: track.artistName,
            artworkURL: track.artworkURL,
            durationText: track.duration?.musicDurationText,
            accessory: accessory
        )
    }
}
