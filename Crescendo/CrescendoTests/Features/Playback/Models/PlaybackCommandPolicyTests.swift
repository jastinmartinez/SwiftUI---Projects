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

    @Test(arguments: commandsUnaffectedByPendingRepeat)
    func pendingRepeatDoesNotBlockUnrelatedCommands(
        command: PlaybackCommand
    ) {
        let policy = makePolicy(queue: .changingRepeat)

        #expect(policy.allows(command))
    }

    @Test(arguments: commandsUnaffectedByPendingShuffle)
    func pendingShuffleDoesNotBlockUnrelatedCommands(
        command: PlaybackCommand
    ) {
        let policy = makePolicy(queue: .changingShuffle)

        #expect(policy.allows(command))
    }
}

// MARK: - Command Policy Cases

private let playPauseCases = [
    CommandPolicyCase(
        name: "allowed with embedded playback and a queue",
        command: .playPause,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked without embedded playback",
        command: .playPause,
        policy: makePolicy(capabilities: .withoutEmbeddedPlayback),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked without a queue",
        command: .playPause,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "allowed while superseding a pending Stop",
        command: .playPause,
        policy: makePolicy(pendingOperation: .stopping),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked during another status change",
        command: .playPause,
        policy: makePolicy(pendingOperation: .playing),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during queue replacement",
        command: .playPause,
        policy: makePolicy(pendingOperation: .replacingQueue),
        expected: false
    ),
]

private let stopCases = [
    CommandPolicyCase(
        name: "allowed with embedded playback and an active queue",
        command: .stop,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked without embedded playback",
        command: .stop,
        policy: makePolicy(capabilities: .withoutEmbeddedPlayback),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked without an active queue",
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
        name: "allowed during queue replacement",
        command: .stop,
        policy: makePolicy(
            queue: .empty,
            pendingOperation: .replacingQueue
        ),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked during an unresolved status change",
        command: .stop,
        policy: makePolicy(pendingOperation: .playing),
        expected: false
    ),
]

private let seekCases = [
    CommandPolicyCase(
        name: "allowed with seeking support and positive duration",
        command: .seek,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked without seeking support",
        command: .seek,
        policy: makePolicy(capabilities: .withoutSeeking),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked without a current item",
        command: .seek,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked without a known duration",
        command: .seek,
        policy: makePolicy(queue: .populated(duration: nil)),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked for zero duration",
        command: .seek,
        policy: makePolicy(queue: .populated(duration: 0)),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked for negative duration",
        command: .seek,
        policy: makePolicy(queue: .populated(duration: -1)),
        expected: false
    ),
]

private let queueTransitionCases = [
    CommandPolicyCase(
        name: "previous is allowed with an active queue",
        command: .previous,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "next is allowed with an active queue",
        command: .next,
        policy: makePolicy(),
        expected: true
    ),
    CommandPolicyCase(
        name: "blocked without queue-transition support",
        command: .next,
        policy: makePolicy(capabilities: .withoutQueueTransitions),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked without an active item",
        command: .previous,
        policy: makePolicy(queue: .empty),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during queue replacement",
        command: .next,
        policy: makePolicy(pendingOperation: .replacingQueue),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending queue transition",
        command: .previous,
        policy: makePolicy(queue: .transitioning),
        expected: false
    ),
    CommandPolicyCase(
        name: "allowed during a pending status change",
        command: .next,
        policy: makePolicy(pendingOperation: .playing),
        expected: true
    ),
]

private let repeatChangeCases = [
    CommandPolicyCase(
        name: "allowed with an active item and multiple supported modes",
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
        name: "blocked during queue replacement",
        command: .repeatMode,
        policy: makePolicy(pendingOperation: .replacingQueue),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending Repeat change",
        command: .repeatMode,
        policy: makePolicy(queue: .changingRepeat),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked with only one supported Repeat mode",
        command: .repeatMode,
        policy: makePolicy(capabilities: .withOneRepeatMode),
        expected: false
    ),
    CommandPolicyCase(
        name: "allowed during a pending Shuffle change",
        command: .repeatMode,
        policy: makePolicy(queue: .changingShuffle),
        expected: true
    ),
]

private let shuffleChangeCases = [
    CommandPolicyCase(
        name: "allowed with an active item and Shuffle support",
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
        name: "blocked during queue replacement",
        command: .shuffleMode,
        policy: makePolicy(pendingOperation: .replacingQueue),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked during a pending Shuffle change",
        command: .shuffleMode,
        policy: makePolicy(queue: .changingShuffle),
        expected: false
    ),
    CommandPolicyCase(
        name: "blocked without Shuffle support",
        command: .shuffleMode,
        policy: makePolicy(capabilities: .withoutShuffle),
        expected: false
    ),
    CommandPolicyCase(
        name: "allowed during a pending Repeat change",
        command: .shuffleMode,
        policy: makePolicy(queue: .changingRepeat),
        expected: true
    ),
]

private let commandsUnaffectedByPendingRepeat: [PlaybackCommand] = [
    .shuffleMode,
    .previous,
    .next,
    .seek,
    .playPause,
    .stop,
]

private let commandsUnaffectedByPendingShuffle: [PlaybackCommand] = [
    .repeatMode,
    .previous,
    .next,
    .seek,
    .playPause,
    .stop,
]

struct CommandPolicyCase: CustomTestStringConvertible {
    let name: String
    let command: PlaybackCommand
    let policy: PlaybackCommandPolicy
    let expected: Bool

    var testDescription: String { name }
}

// MARK: - Policy Factory

private func makePolicy(
    capabilities: MusicProviderCapabilities = .allEnabled,
    queue: PlaybackQueueFeature.State = .populated,
    status: PlaybackStatus = .paused,
    pendingOperation: PlaybackFeature.PendingOperation? = nil,
    isResettingProvider: Bool = false
) -> PlaybackCommandPolicy {
    PlaybackCommandPolicy(
        capabilities: capabilities,
        queue: queue,
        status: status,
        pendingOperation: pendingOperation,
        isResettingProvider: isResettingProvider
    )
}

// MARK: - Test Values

extension MusicProviderCapabilities {
    fileprivate static let withoutEmbeddedPlayback = Self(
        supportsCatalogSearch: true,
        supportsEmbeddedPlayback: false,
        supportsSeeking: true,
        supportsQueueReplacement: true,
        supportsQueueTransitions: true,
        supportedRepeatModes: [.off, .all, .one],
        supportsShuffle: true
    )

    fileprivate static let withoutSeeking = Self(
        supportsCatalogSearch: true,
        supportsEmbeddedPlayback: true,
        supportsSeeking: false,
        supportsQueueReplacement: true,
        supportsQueueTransitions: true,
        supportedRepeatModes: [.off, .all, .one],
        supportsShuffle: true
    )

    fileprivate static let withoutQueueTransitions = Self(
        supportsCatalogSearch: true,
        supportsEmbeddedPlayback: true,
        supportsSeeking: true,
        supportsQueueReplacement: true,
        supportsQueueTransitions: false,
        supportedRepeatModes: [.off, .all, .one],
        supportsShuffle: true
    )

    fileprivate static let withOneRepeatMode = Self(
        supportsCatalogSearch: true,
        supportsEmbeddedPlayback: true,
        supportsSeeking: true,
        supportsQueueReplacement: true,
        supportsQueueTransitions: true,
        supportedRepeatModes: [.off],
        supportsShuffle: true
    )

    fileprivate static let withoutShuffle = Self(
        supportsCatalogSearch: true,
        supportsEmbeddedPlayback: true,
        supportsSeeking: true,
        supportsQueueReplacement: true,
        supportsQueueTransitions: true,
        supportedRepeatModes: [.off, .all, .one],
        supportsShuffle: false
    )
}

extension PlaybackFeature.PendingOperation {
    fileprivate static let replacingQueue = Self.queueReplacement(
        .init(
            requestID: UUID(0),
            songs: PlaybackQueueFeature.State.populated.songs,
            startingItemID: MusicItemID(
                providerID: "fake",
                nativeID: "current"
            )
        )
    )

    fileprivate static let playing = Self.statusChange(
        .init(requestID: UUID(0), target: .playing)
    )

    fileprivate static let stopping = Self.statusChange(
        .init(requestID: UUID(0), target: .stopped)
    )
}

extension PlaybackQueueFeature.State {
    fileprivate static let empty = Self(
        songs: [],
        currentItemID: nil,
        repeatMode: .off,
        shuffleMode: .off,
        pendingQueueTransition: nil,
        pendingRepeatChange: nil,
        pendingShuffleChange: nil
    )

    fileprivate static let populated = populated(duration: 180)

    fileprivate static let transitioning = Self(
        songs: populated.songs,
        currentItemID: populated.currentItemID,
        repeatMode: .off,
        shuffleMode: .off,
        pendingQueueTransition: .init(
            requestID: UUID(0),
            direction: .next
        ),
        pendingRepeatChange: nil,
        pendingShuffleChange: nil
    )

    fileprivate static let changingRepeat = Self(
        songs: populated.songs,
        currentItemID: populated.currentItemID,
        repeatMode: .off,
        shuffleMode: .off,
        pendingQueueTransition: nil,
        pendingRepeatChange: .init(
            requestID: UUID(0),
            target: .all
        ),
        pendingShuffleChange: nil
    )

    fileprivate static let changingShuffle = Self(
        songs: populated.songs,
        currentItemID: populated.currentItemID,
        repeatMode: .off,
        shuffleMode: .off,
        pendingQueueTransition: nil,
        pendingRepeatChange: nil,
        pendingShuffleChange: .init(
            requestID: UUID(0),
            target: .songs
        )
    )

    fileprivate static func populated(duration: TimeInterval?) -> Self {
        let song = SongSummary(
            id: MusicItemID(providerID: "fake", nativeID: "current"),
            title: "Current",
            artistName: "Artist",
            artworkURL: nil,
            duration: duration
        )
        return Self(
            songs: IdentifiedArray(uniqueElements: [song]),
            currentItemID: song.id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
    }
}
