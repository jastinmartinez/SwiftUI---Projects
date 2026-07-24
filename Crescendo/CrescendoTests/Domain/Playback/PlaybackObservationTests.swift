import Testing

@testable import Crescendo

struct PlaybackObservationTests {
    @Test
    func snapshotDescribesCurrentPlayerState() {
        let trackID = TrackID(providerID: .jamendo, nativeID: "42")
        let snapshot = PlaybackSnapshot(
            currentTrackID: trackID,
            status: .waiting,
            position: 12,
            duration: 180
        )

        #expect(
            PlaybackObservation.snapshot(snapshot)
                != .completed(trackID)
        )
    }

    @Test
    func failureCanIdentifyTheAffectedTrack() {
        let trackID = TrackID(providerID: .jamendo, nativeID: "42")

        #expect(
            PlaybackObservation.failed(trackID, .playbackFailed)
                != .failed(nil, .playbackFailed)
        )
    }
}
