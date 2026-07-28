@preconcurrency import AVFoundation

@MainActor
final class AVPlayerItemRegistry {
    private var trackIDsByItem: [ObjectIdentifier: TrackID] = [:]

    func register(_ item: AVPlayerItem, trackID: TrackID) {
        trackIDsByItem[ObjectIdentifier(item)] = trackID
    }

    func trackID(for item: AVPlayerItem?) -> TrackID? {
        guard let item else { return nil }
        return trackIDsByItem[ObjectIdentifier(item)]
    }

    func remove(_ item: AVPlayerItem) {
        trackIDsByItem[ObjectIdentifier(item)] = nil
    }
}
