import Testing

@testable import Crescendo

struct PlaybackQueueOrderTests {
    @Test
    func derivesAdjacentAndFollowingTracks() {
        let first = makeTrackID("1")
        let second = makeTrackID("2")
        let third = makeTrackID("3")
        let order = PlaybackQueueOrder(
            trackIDs: [first, second, third]
        )

        #expect(order.previousTrackID(before: first) == nil)
        #expect(order.previousTrackID(before: second) == first)
        #expect(order.nextTrackID(after: second) == third)
        #expect(order.nextTrackID(after: third) == nil)
        #expect(order.trackIDs(after: first) == [second, third])
    }

    @Test
    func unknownTrackHasNoTraversalResults() {
        let order = PlaybackQueueOrder(trackIDs: [makeTrackID("1")])
        let unknown = makeTrackID("unknown")

        #expect(order.previousTrackID(before: unknown) == nil)
        #expect(order.nextTrackID(after: unknown) == nil)
        #expect(order.trackIDs(after: unknown).isEmpty)
    }
}

// MARK: - Helpers

private func makeTrackID(_ nativeID: String) -> TrackID {
    TrackID(providerID: .jamendo, nativeID: nativeID)
}
