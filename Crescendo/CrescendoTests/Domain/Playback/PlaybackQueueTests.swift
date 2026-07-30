import ComposableArchitecture
import Testing

@testable import Crescendo

struct PlaybackQueueTests {
    @Test
    func replacementRequiresAKnownCurrentTrack() {
        let tracks = makeTracks()
        let unknownTrackID = TrackID(
            providerID: "fake",
            nativeID: "unknown"
        )

        let queue = PlaybackQueue(
            tracks: IdentifiedArray(uniqueElements: tracks),
            startingAt: unknownTrackID
        )

        #expect(queue == nil)
    }

    @Test
    func validationRequiresEveryTrackExactlyOnceInTheOrder() {
        let tracks = makeTracks()
        let identifiedTracks = IdentifiedArray(uniqueElements: tracks)

        let missingTrack = PlaybackQueue(
            tracks: identifiedTracks,
            playbackOrder: PlaybackQueueOrder(
                trackIDs: [tracks[0].id, tracks[1].id]
            ),
            currentTrackID: tracks[0].id,
            repeatMode: .off,
            shuffleMode: .off
        )
        let duplicateTrack = PlaybackQueue(
            tracks: identifiedTracks,
            playbackOrder: PlaybackQueueOrder(
                trackIDs: [
                    tracks[0].id,
                    tracks[1].id,
                    tracks[1].id,
                ]
            ),
            currentTrackID: tracks[0].id,
            repeatMode: .off,
            shuffleMode: .off
        )

        #expect(missingTrack == nil)
        #expect(duplicateTrack == nil)
    }

    @Test
    func confirmedQueueOwnsCurrentAndTraversalProjections() throws {
        let tracks = makeTracks()
        let queue = try #require(
            PlaybackQueue(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [
                        tracks[2].id,
                        tracks[0].id,
                        tracks[1].id,
                    ]
                ),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .tracks
            )
        )

        #expect(queue.currentTrack == tracks[0])
        #expect(queue.previousTrackID == tracks[2].id)
        #expect(queue.nextTrackID == tracks[1].id)
        #expect(queue.upNextTracks == [tracks[1]])
    }

    @Test
    func navigationChangesOnlyTheCurrentTrack() throws {
        let tracks = makeTracks()
        let queue = try #require(makeQueue(tracks: tracks))

        let navigated = try #require(queue.navigating(to: tracks[2].id))

        #expect(navigated.currentTrackID == tracks[2].id)
        #expect(navigated.tracks == queue.tracks)
        #expect(navigated.playbackOrder == queue.playbackOrder)
        #expect(navigated.repeatMode == queue.repeatMode)
        #expect(navigated.shuffleMode == queue.shuffleMode)
    }

    @Test
    func navigationRejectsAnUnknownTrack() throws {
        let tracks = makeTracks()
        let queue = try #require(makeQueue(tracks: tracks))
        let unknownTrackID = TrackID(
            providerID: "fake",
            nativeID: "unknown"
        )

        #expect(queue.navigating(to: unknownTrackID) == nil)
    }

    @Test
    func repeatCycleAndCompletionStayInsideTheAggregate() throws {
        let tracks = makeTracks()
        let queue = try #require(makeQueue(tracks: tracks))

        let repeatAll = queue.cyclingRepeatMode()
        let repeatOne = repeatAll.cyclingRepeatMode()
        let repeatOff = repeatOne.cyclingRepeatMode()

        #expect(repeatAll.repeatMode == .all)
        #expect(repeatOne.repeatMode == .one)
        #expect(repeatOff.repeatMode == .off)
        #expect(
            repeatOne.automaticTrackID(after: tracks[0].id)
                == tracks[0].id
        )

        let finalQueue = try #require(
            queue.navigating(to: tracks[2].id)
        )
        #expect(
            finalQueue.cyclingRepeatMode().automaticTrackID(
                after: tracks[2].id
            ) == tracks[0].id
        )
        #expect(
            finalQueue.automaticTrackID(after: tracks[1].id) == nil
        )
    }

    @Test
    func shuffleAcceptsOnlyAnExactPermutation() throws {
        let tracks = makeTracks()
        let queue = try #require(makeQueue(tracks: tracks))
        let shuffledTrackIDs = [
            tracks[2].id,
            tracks[0].id,
            tracks[1].id,
        ]

        let shuffled = try #require(
            queue.enablingShuffle(with: shuffledTrackIDs)
        )

        #expect(shuffled.playbackOrder.trackIDs == shuffledTrackIDs)
        #expect(shuffled.shuffleMode == .tracks)
        #expect(
            queue.enablingShuffle(
                with: [tracks[0].id, tracks[1].id]
            ) == nil
        )
        #expect(
            queue.enablingShuffle(
                with: [
                    tracks[0].id,
                    tracks[1].id,
                    tracks[1].id,
                ]
            ) == nil
        )
    }

    @Test
    func disablingShuffleRestoresSourceOrder() throws {
        let tracks = makeTracks()
        let queue = try #require(makeQueue(tracks: tracks))
        let shuffled = try #require(
            queue.enablingShuffle(
                with: [
                    tracks[2].id,
                    tracks[0].id,
                    tracks[1].id,
                ]
            )
        )

        let canonical = shuffled.disablingShuffle()

        #expect(canonical.playbackOrder.trackIDs == tracks.map(\.id))
        #expect(canonical.shuffleMode == .off)
        #expect(canonical.currentTrackID == tracks[0].id)
    }

    private func makeQueue(tracks: [Track]) -> PlaybackQueue? {
        PlaybackQueue(
            tracks: IdentifiedArray(uniqueElements: tracks),
            startingAt: tracks[0].id
        )
    }

    private func makeTracks() -> [Track] {
        (0..<3).map { index in
            Track(
                id: TrackID(
                    providerID: "fake",
                    nativeID: "\(index)"
                ),
                title: "Track \(index)",
                artistName: "Artist",
                albumTitle: nil,
                artworkURL: nil,
                duration: 180
            )
        }
    }
}
