import Foundation

// Adapts one confirmed Library membership into row presentation.
//
// The adapter owns localized metadata fallback and selection mapping only. It
// does not render, hold feature state, navigate, resolve files, or play audio.
extension LibraryTrackRowView.Model {
    /// Projects one Library item into localized row values and selection.
    ///
    /// - Parameters:
    ///   - item: The confirmed Library membership to present.
    ///   - onTap: The feature action bridge receiving the selected identity.
    init(
        _ item: Library.Item,
        onTap: @escaping (TrackID) -> Void
    ) {
        self.init(
            id: item.id,
            title: item.track.title,
            artist: item.track.artistName.libraryDisplayValue
                ?? Locs.Common.unknownArtist,
            album: item.track.albumTitle.libraryDisplayValue
                ?? Locs.Library.unknownAlbum,
            artworkURL: item.track.artworkURL,
            onTap: { onTap(item.id) }
        )
    }
}

private extension Optional where Wrapped == String {
    var libraryDisplayValue: String? {
        guard let value = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }
}
