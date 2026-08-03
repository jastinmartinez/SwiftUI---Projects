import Foundation
import IdentifiedCollections
import Testing

@testable import Crescendo

struct PlaybackNowPlayingProjectionTests {
    @Test
    func missingConfirmedQueueProducesNoProjection() {
        let state = makeState(queue: nil)

        let projection = PlaybackNowPlayingClient.Projection(
            playback: state
        )

        #expect(projection == nil)
    }

    @Test
    func confirmedStateProducesCurrentItemTransportAndTimeline() throws {
        let artworkURL = try #require(
            URL(string: "https://example.com/confirmed.jpg")
        )
        let tracks = [
            makeTrack(nativeID: "first"),
            makeTrack(
                nativeID: "confirmed",
                title: "Confirmed Song",
                artistName: "Confirmed Artist",
                albumTitle: "Confirmed Album",
                artworkURL: artworkURL
            ),
        ]
        let queue = try #require(
            PlaybackQueue(
                tracks: IdentifiedArray(uniqueElements: tracks),
                startingAt: tracks[1].id
            )
        )
        let state = makeState(
            queue: queue,
            confirmedPosition: 42,
            duration: 180,
            status: .playing
        )

        let projection = try #require(
            PlaybackNowPlayingClient.Projection(playback: state)
        )
        let expectedTrackID = TrackID(
            providerID: .library,
            nativeID: "confirmed"
        )

        #expect(projection.item.id == expectedTrackID)
        #expect(projection.item.title == "Confirmed Song")
        #expect(projection.item.artistName == "Confirmed Artist")
        #expect(projection.item.albumTitle == "Confirmed Album")
        #expect(projection.item.artworkURL == artworkURL)
        #expect(projection.transport.status == .playing)
        #expect(projection.timeline.position == 42)
        #expect(projection.timeline.duration == 180)
    }

    @Test
    func draftTimelinePositionDoesNotReplaceConfirmedPosition() throws {
        let track = makeTrack(nativeID: "timeline")
        let queue = try #require(
            PlaybackQueue(
                tracks: [track],
                startingAt: track.id
            )
        )
        let state = makeState(
            queue: queue,
            confirmedPosition: 25,
            duration: 200,
            interaction: .dragging(position: 90)
        )

        let projection = try #require(
            PlaybackNowPlayingClient.Projection(playback: state)
        )

        #expect(projection.timeline.position == 25)
    }

    @Test
    func pendingTransitionDoesNotReplaceConfirmedItem() throws {
        let confirmedTrack = makeTrack(
            nativeID: "confirmed",
            title: "Confirmed"
        )
        let pendingTrack = makeTrack(
            nativeID: "pending",
            title: "Pending"
        )
        let confirmedQueue = try #require(
            PlaybackQueue(
                tracks: [confirmedTrack],
                startingAt: confirmedTrack.id
            )
        )
        let pendingQueue = try #require(
            PlaybackQueue(
                tracks: [pendingTrack],
                startingAt: pendingTrack.id
            )
        )
        let state = makeState(
            queue: confirmedQueue,
            pendingChanges: .init(
                active: .replacement(pendingQueue),
                followUp: nil
            ),
            transition: .init(
                phase: .starting(
                    .init(
                        target: pendingTrack,
                        baselineTrackID: confirmedTrack.id
                    )
                )
            )
        )

        let projection = try #require(
            PlaybackNowPlayingClient.Projection(playback: state)
        )

        #expect(projection.item.title == "Confirmed")
        #expect(projection.item.id == confirmedTrack.id)
    }

    @Test
    func queueContextUsesConfirmedPlaybackOrder() throws {
        let tracks = [
            makeTrack(nativeID: "source-zero"),
            makeTrack(nativeID: "source-one"),
            makeTrack(nativeID: "source-two"),
        ]
        let queue = try #require(
            PlaybackQueue(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [tracks[2].id, tracks[0].id, tracks[1].id]
                ),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .tracks
            )
        )

        let projection = try #require(
            PlaybackNowPlayingClient.Projection(
                playback: makeState(queue: queue)
            )
        )

        #expect(projection.queue.index == 1)
        #expect(projection.queue.count == 3)
    }
}

private func makeState(
    queue: PlaybackQueue?,
    pendingChanges: PlaybackQueueReducer.PendingChanges? = nil,
    confirmedPosition: TimeInterval = 0,
    duration: TimeInterval? = nil,
    interaction: PlaybackTimelineReducer.Interaction = .idle,
    status: PlaybackStatus = .paused,
    transition: PlaybackTransitionReducer.State? = nil
) -> PlaybackReducer.State {
    PlaybackReducer.State(
        queue: PlaybackQueueReducer.State(
            current: queue,
            pendingChanges: pendingChanges
        ),
        timeline: PlaybackTimelineReducer.State(
            confirmedPosition: confirmedPosition,
            duration: duration,
            isSeekable: duration != nil,
            interaction: interaction
        ),
        session: PlaybackSessionReducer.State(
            status: status,
            pendingStatusChange: nil
        ),
        transition: transition,
        failureNotice: nil,
        isPlayerPresented: false
    )
}

private func makeTrack(
    nativeID: String,
    title: String? = nil,
    artistName: String? = nil,
    albumTitle: String? = nil,
    artworkURL: URL? = nil
) -> Track {
    Track(
        id: TrackID(
            providerID: .library,
            nativeID: nativeID
        ),
        title: title ?? nativeID,
        artistName: artistName,
        albumTitle: albumTitle,
        artworkURL: artworkURL,
        duration: 180
    )
}
