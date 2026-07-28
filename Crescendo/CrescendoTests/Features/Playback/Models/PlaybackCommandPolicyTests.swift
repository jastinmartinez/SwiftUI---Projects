import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

struct PlaybackCommandPolicyTests {
    @Test(arguments: PlaybackCommand.allCases)
    func providerResetBlocksEveryCommand(_ command: PlaybackCommand) {
        #expect(!makePolicy(isResettingProvider: true).allows(command))
    }

    @Test(arguments: playPauseCases)
    func playPauseFollowsSharedPolicy(_ testCase: CommandPolicyCase) {
        #expect(
            testCase.policy.allows(testCase.command) == testCase.expected
        )
    }

    @Test(arguments: stopCases)
    func stopFollowsSharedPolicy(_ testCase: CommandPolicyCase) {
        #expect(
            testCase.policy.allows(testCase.command) == testCase.expected
        )
    }

    @Test(arguments: seekCases)
    func seekFollowsSharedPolicy(_ testCase: CommandPolicyCase) {
        #expect(
            testCase.policy.allows(testCase.command) == testCase.expected
        )
    }

    @Test(arguments: queueTransitionCases)
    func queueTransitionsFollowSharedPolicy(_ testCase: CommandPolicyCase) {
        #expect(
            testCase.policy.allows(testCase.command) == testCase.expected
        )
    }

    @Test(arguments: repeatChangeCases)
    func repeatChangesFollowSharedPolicy(_ testCase: CommandPolicyCase) {
        #expect(
            testCase.policy.allows(testCase.command) == testCase.expected
        )
    }

    @Test(arguments: shuffleChangeCases)
    func shuffleChangesFollowSharedPolicy(_ testCase: CommandPolicyCase) {
        #expect(
            testCase.policy.allows(testCase.command) == testCase.expected
        )
    }
}

// MARK: - Command Policy Cases

private let playPauseCases = [
    CommandPolicyCase(
        name: "allowed with a current track",
        command: .playPause,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked without a current track",
        command: .playPause,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending playback transition",
        command: .playPause,
        policy: makePolicy(pendingPlaybackTransition: .resolving),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending status change",
        command: .playPause,
        policy: makePolicy(pendingStatusChange: .playing),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending Stop",
        command: .playPause,
        policy: makePolicy(pendingStatusChange: .stopping),
        expected: false
    ),
]

private let stopCases = [
    CommandPolicyCase(
        name: "allowed with an active track",
        command: .stop,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked without a current track",
        command: .stop,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked when playback is already stopped",
        command: .stop,
        policy: makePolicy(status: .stopped),
        expected: false
    ),
    CommandPolicyCase(
        name: "allowed during a pending playback transition",
        command: .stop,
        policy: makePolicy(pendingPlaybackTransition: .resolving),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked during an unresolved status change",
        command: .stop,
        policy: makePolicy(pendingStatusChange: .playing),
        expected: false
    ),
]

private let seekCases = [
    CommandPolicyCase(
        name: "allowed for a confirmed seekable positive timeline",
        command: .seek,
        policy: makePolicy(isSeekable: true),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked when the player reports a nonseekable item",
        command: .seek,
        policy: makePolicy(isSeekable: false),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked without a current item",
        command: .seek,
        policy: makePolicy(queue: .empty, isSeekable: true),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked when only catalog metadata has a duration",
        command: .seek,
        policy: makePolicy(
            queue: .populated,
            duration: nil,
            isSeekable: true
        ),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending playback transition",
        command: .seek,
        policy: makePolicy(
            isSeekable: true,
            pendingPlaybackTransition: .resolving
        ),
        expected: false
    ),
]

private let queueTransitionCases = [
    CommandPolicyCase(
        name: "previous is allowed inside the queue",
        command: .previous,
        policy: makePolicy(queue: .sequence(currentIndex: 1)),
        expected: true
    ),
    CommandPolicyCase(
        name: "next is allowed inside the queue",
        command: .next,
        policy: makePolicy(queue: .sequence(currentIndex: 1)),
        expected: true
    ),
    CommandPolicyCase(
        name: "previous is blocked at the first track",
        command: .previous,
        policy: makePolicy(queue: .sequence(currentIndex: 0)),
        expected: false
    ),
    CommandPolicyCase(
        name: "next is blocked at the final track",
        command: .next,
        policy: makePolicy(queue: .sequence(currentIndex: 2)),
        expected: false
    ),
    CommandPolicyCase(
        name: "previous is blocked without an active item",
        command: .previous,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "next is blocked without an active item",
        command: .next,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "previous is blocked during a pending playback transition",
        command: .previous,
        policy: makePolicy(
            queue: .sequence(currentIndex: 1),
            pendingPlaybackTransition: .resolving
        ),
        expected: false
    ),
    CommandPolicyCase(
        name: "next is blocked during a pending playback transition",
        command: .next,
        policy: makePolicy(
            queue: .sequence(currentIndex: 1),
            pendingPlaybackTransition: .resolving
        ),
        expected: false
    ),
    CommandPolicyCase(
        name: "next is allowed during a pending status change",
        command: .next,
        policy: makePolicy(
            queue: .sequence(currentIndex: 1),
            pendingStatusChange: .playing
        ),
        expected: true
    ),
]

private let repeatChangeCases = [
    CommandPolicyCase(
        name: "allowed with an active item",
        command: .repeatMode,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked without an active item",
        command: .repeatMode,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending playback transition",
        command: .repeatMode,
        policy: makePolicy(pendingPlaybackTransition: .resolving),
        expected: false
    ),
]

private let shuffleChangeCases = [
    CommandPolicyCase(
        name: "allowed with an active item",
        command: .shuffleMode,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked without an active item",
        command: .shuffleMode,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending playback transition",
        command: .shuffleMode,
        policy: makePolicy(pendingPlaybackTransition: .resolving),
        expected: false
    ),
]

// MARK: - Policy Factory

private func makePolicy(
    queue: PlaybackQueueFeature.State = .populated,
    status: PlaybackStatus = .paused,
    duration: TimeInterval? = 180,
    isSeekable: Bool = true,
    pendingPlaybackTransition: PendingPlaybackTransition? = nil,
    pendingStatusChange: PlaybackFeature.PendingStatusChange? = nil,
    isResettingProvider: Bool = false
) -> PlaybackCommandPolicy {
    PlaybackCommandPolicy(
        queue: queue,
        status: status,
        duration: duration,
        isSeekable: isSeekable,
        pendingPlaybackTransition: pendingPlaybackTransition,
        pendingStatusChange: pendingStatusChange,
        isResettingProvider: isResettingProvider
    )
}

// MARK: - Test Values

extension PendingPlaybackTransition {
    fileprivate static let resolving = Self(
        requestID: UUID(0),
        queue: PlaybackQueueFeature.State.populated.tracks,
        targetTrackID: TrackID(
            providerID: "fake",
            nativeID: "current"
        )
    )
}

extension PlaybackFeature.PendingStatusChange {
    fileprivate static let playing = Self(
        requestID: UUID(0),
        target: .playing
    )

    fileprivate static let stopping = Self(
        requestID: UUID(0),
        target: .stopped
    )
}

extension PlaybackQueueFeature.State {
    fileprivate static let empty = Self(
        tracks: [],
        playbackOrder: PlaybackQueueOrder(trackIDs: []),
        currentTrackID: nil,
        repeatMode: .off,
        shuffleMode: .off
    )

    fileprivate static let populated = populated(duration: 180)

    fileprivate static func populated(duration: TimeInterval?) -> Self {
        let song = Track(
            id: TrackID(providerID: "fake", nativeID: "current"),
            title: "Current",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: duration
        )
        return Self(
            tracks: IdentifiedArray(uniqueElements: [song]),
            playbackOrder: PlaybackQueueOrder(trackIDs: [song.id]),
            currentTrackID: song.id,
            repeatMode: .off,
            shuffleMode: .off
        )
    }

    fileprivate static func sequence(currentIndex: Int) -> Self {
        let songs = (1...3).map { index in
            Track(
                id: TrackID(providerID: "fake", nativeID: "song-\(index)"),
                title: "Song \(index)",
                artistName: "Artist",
                albumTitle: nil,
                artworkURL: nil,
                duration: 180
            )
        }
        let tracks = IdentifiedArray(uniqueElements: songs)
        return Self(
            tracks: tracks,
            playbackOrder: PlaybackQueueOrder(trackIDs: Array(tracks.ids)),
            currentTrackID: songs[currentIndex].id,
            repeatMode: .off,
            shuffleMode: .off
        )
    }
}
