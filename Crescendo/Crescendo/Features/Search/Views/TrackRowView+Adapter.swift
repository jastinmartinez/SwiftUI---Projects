extension TrackRowView.Model {
    /// Adapts provider-neutral track metadata into the row presentation contract.
    init(_ song: Track) {
        self.init(
            id: song.id,
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            durationText: song.duration?.musicDurationText
        )
    }
}
