extension SongRowView.Model {
    /// Adapts provider-neutral song metadata into the row presentation contract.
    init(_ song: SongSummary) {
        self.init(
            id: song.id,
            title: song.title,
            artistName: song.artistName,
            artworkURL: song.artworkURL,
            durationText: song.duration?.musicDurationText
        )
    }
}
