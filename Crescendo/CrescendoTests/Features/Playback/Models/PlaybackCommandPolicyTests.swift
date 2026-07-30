import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

struct PlaybackCommandPolicyTests {
    @Test
    func playPauseRequiresConfirmedTrackAndStableChildren() {
        #expect(makePolicy().allows(.playPause))
        #expect(!makePolicy(queue: .empty).allows(.playPause))
        #expect(
            !makePolicy(transition: makeStartingTransition())
                .allows(.playPause)
        )
        #expect(
            !makePolicy(pendingTarget: .paused).allows(.playPause)
        )
    }

    @Test
    func stopRemainsAvailableWhileTransitionOwnsCleanup() {
        #expect(
            makePolicy(transition: makeStartingTransition())
                .allows(.stop)
        )
    }

    @Test @MainActor
    func stopIsBlockedAfterTransitionRetainsTheRequest() async {
        let intent = PlaybackTransitionFeature.Intent(
            targetTrackID: TrackID(
                providerID: "fake",
                nativeID: "pending"
            ),
            baselineTrackID: TrackID(
                providerID: "fake",
                nativeID: "current"
            )
        )
        let transaction = PlaybackTransitionFeature.Transaction(
            requestID: UUID(0),
            intent: intent
        )
        let resource = PlaybackResource(
            trackID: intent.targetTrackID,
            location: .localFile(
                URL(fileURLWithPath: "/tmp/pending.m4a")
            )
        )
        let store = TestStore(
            initialState: PlaybackTransitionFeature.State(
                phase: .starting(intent)
            )
        ) {
            PlaybackTransitionFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [
                    "fake": PlaybackResourceClient(
                        resolve: { _ in resource }
                    )
                ]
            )
            $0.playbackItem.load = { _, _ in
                try await Task.sleep(for: .seconds(60))
            }
            $0.playbackItem.rollback = { _ in }
        }

        await store.send(.start) {
            $0.phase = .preparing(
                transaction,
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolved(
                requestID: UUID(0),
                resource: resource
            )
        ) {
            $0.phase = .preparing(
                transaction,
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }

        #expect(makePolicy(transition: store.state).allows(.stop))

        await store.send(.stopRequested) {
            $0.phase = .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .cancellation,
                    followUp: .stop
                )
            )
        }

        #expect(!makePolicy(transition: store.state).allows(.stop))

        await store.receive(.rollbackRequested(requestID: UUID(0)))
        await store.receive(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(.delegate(.completed(.stopReady)))
    }

    @Test
    func stopRequiresConfirmedTrackAndStableSession() {
        #expect(!makePolicy(queue: .empty).allows(.stop))
        #expect(!makePolicy(status: .stopped).allows(.stop))
        #expect(!makePolicy(pendingTarget: .playing).allows(.stop))
        #expect(!makePolicy(pendingTarget: .paused).allows(.stop))
        #expect(!makePolicy(pendingTarget: .stopped).allows(.stop))
    }

    @Test
    func seekRequiresConfirmedBoundsAndNoTransition() {
        #expect(makePolicy().allows(.seek))
        #expect(!makePolicy(queue: .empty).allows(.seek))
        #expect(!makePolicy(duration: nil).allows(.seek))
        #expect(!makePolicy(duration: 0).allows(.seek))
        #expect(!makePolicy(isSeekable: false).allows(.seek))
        #expect(
            !makePolicy(transition: makeStartingTransition())
                .allows(.seek)
        )
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
                transition: makeStartingTransition()
            )
            .allows(.previous)
        )
        #expect(
            !makePolicy(
                queue: .sequence(currentIndex: 1),
                transition: makeStartingTransition()
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
            !makePolicy(transition: makeStartingTransition())
                .allows(.repeatMode)
        )
        #expect(
            !makePolicy(transition: makeStartingTransition())
                .allows(.shuffleMode)
        )
    }
}

private func makePolicy(
    queue: PlaybackQueueFeature.State = .populated,
    status: PlaybackStatus = .playing,
    pendingTarget: PlaybackSessionFeature.PendingStatusChange.Target? = nil,
    transition: PlaybackTransitionFeature.State? = nil,
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
        transition: transition
    )
}

private func makeStartingTransition() -> PlaybackTransitionFeature.State {
    PlaybackTransitionFeature.State(
        phase: .starting(
            .init(
                targetTrackID: TrackID(
                    providerID: "fake",
                    nativeID: "pending"
                ),
                baselineTrackID: nil
            )
        )
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
