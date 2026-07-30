import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

struct PlaybackCommandPolicyTests {
    @Test
    func playPauseRequiresConfirmedTrackAndStableChildren() {
        #expect(makePolicy().allows(.playPause))
        #expect(!makePolicy(queue: .empty).allows(.playPause))
        #expect(!makePolicy(hasTransition: true).allows(.playPause))
        #expect(
            !makePolicy(pendingTarget: .paused).allows(.playPause)
        )
    }

    @Test
    func stopRemainsAvailableWhileTransitionOwnsCleanup() {
        #expect(makePolicy(hasTransition: true).allows(.stop))
    }

    @Test
    func stopRequiresConfirmedTrackAndStableSession() {
        #expect(!makePolicy(queue: .empty).allows(.stop))
        #expect(!makePolicy(status: .stopped).allows(.stop))
        #expect(!makePolicy(pendingTarget: .playing).allows(.stop))
        #expect(!makePolicy(pendingTarget: .stopped).allows(.stop))
    }

    @Test
    func seekRequiresConfirmedBoundsAndNoTransition() {
        #expect(makePolicy().allows(.seek))
        #expect(!makePolicy(queue: .empty).allows(.seek))
        #expect(!makePolicy(duration: nil).allows(.seek))
        #expect(!makePolicy(duration: 0).allows(.seek))
        #expect(!makePolicy(isSeekable: false).allows(.seek))
        #expect(!makePolicy(hasTransition: true).allows(.seek))
    }

    @Test
    func previousAndNextRequireAnAdjacentTrackAndNoTransition() {
        #expect(
            makePolicy(queue: .sequence(currentIndex: 1))
                .allows(.previous)
        )
        #expect(
            makePolicy(queue: .sequence(currentIndex: 1))
                .allows(.next)
        )
        #expect(
            !makePolicy(queue: .sequence(currentIndex: 0))
                .allows(.previous)
        )
        #expect(
            !makePolicy(queue: .sequence(currentIndex: 2))
                .allows(.next)
        )
        #expect(
            !makePolicy(
                queue: .sequence(currentIndex: 1),
                hasTransition: true
            )
            .allows(.previous)
        )
        #expect(
            !makePolicy(
                queue: .sequence(currentIndex: 1),
                hasTransition: true
            )
            .allows(.next)
        )
    }

    @Test
    func queueModesRequireConfirmedTrackAndNoTransition() {
        #expect(makePolicy().allows(.repeatMode))
        #expect(makePolicy().allows(.shuffleMode))
        #expect(!makePolicy(queue: .empty).allows(.repeatMode))
        #expect(!makePolicy(queue: .empty).allows(.shuffleMode))
        #expect(
            !makePolicy(hasTransition: true).allows(.repeatMode)
        )
        #expect(
            !makePolicy(hasTransition: true).allows(.shuffleMode)
        )
    }
}

private func makePolicy(
    queue: PlaybackQueueFeature.State = .populated,
    status: PlaybackStatus = .playing,
    pendingTarget: PlaybackSessionFeature.PendingStatusChange.Target? = nil,
    hasTransition: Bool = false,
    duration: TimeInterval? = 180,
    isSeekable: Bool = true
) -> PlaybackCommandPolicy {
    PlaybackCommandPolicy(
        queue: queue,
        timeline: PlaybackTimelineFeature.State(
            confirmedPosition: 0,
            duration: duration,
            isSeekable: isSeekable,
            interaction: .idle
        ),
        session: PlaybackSessionFeature.State(
            status: status,
            pendingStatusChange: pendingTarget.map {
                PlaybackSessionFeature.PendingStatusChange(
                    requestID: UUID(0),
                    target: $0
                )
            }
        ),
        transition: hasTransition
            ? PlaybackTransitionFeature.State(
                phase: .starting(
                    .init(
                        targetTrackID: TrackID(
                            providerID: "fake",
                            nativeID: "pending"
                        ),
                        baselineTrackID:
                            queue.current?.currentTrackID
                    )
                )
            )
            : nil
    )
}

extension PlaybackQueueFeature.State {
    fileprivate static let empty = Self(
        current: nil
    )

    fileprivate static let populated = sequence(currentIndex: 1)

    fileprivate static func sequence(currentIndex: Int) -> Self {
        let tracks = (0..<3).map { index in
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
        guard
            let queue = PlaybackQueue(
                tracks: IdentifiedArray(uniqueElements: tracks),
                startingAt: tracks[currentIndex].id
            )
        else {
            preconditionFailure("Expected a valid playback queue fixture")
        }
        return Self(current: queue)
    }
}
