import Foundation

extension Track {
    init?(jamendoTrack: JamendoTrack) {
        guard let audioURL = URL(httpString: jamendoTrack.audio) else {
            return nil
        }
        let albumTitle = jamendoTrack.albumName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: TrackID(providerID: .jamendo, nativeID: jamendoTrack.id),
            title: jamendoTrack.name,
            artistName: jamendoTrack.artistName,
            albumTitle: albumTitle.isEmpty ? nil : albumTitle,
            artworkURL: URL(httpString: jamendoTrack.image),
            duration: TimeInterval(jamendoTrack.duration),
            playbackURL: audioURL
        )
    }
}
