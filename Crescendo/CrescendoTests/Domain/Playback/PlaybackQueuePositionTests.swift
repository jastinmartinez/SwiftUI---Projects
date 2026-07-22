import Testing

@testable import Crescendo

struct PlaybackQueuePositionTests {
    @Test(arguments: [
        (PlaybackNavigationDirection.previous, false),
        (.next, true),
    ])
    func firstEntryExposesOnlyTheNextTransition(
        direction: PlaybackNavigationDirection,
        expected: Bool
    ) {
        let position = PlaybackQueuePosition(
            entryIDs: ["first", "second"],
            currentEntryID: "first"
        )

        #expect(position.canTransition(direction) == expected)
    }

    @Test(arguments: [
        (PlaybackNavigationDirection.previous, true),
        (.next, false),
    ])
    func lastEntryExposesOnlyThePreviousTransition(
        direction: PlaybackNavigationDirection,
        expected: Bool
    ) {
        let position = PlaybackQueuePosition(
            entryIDs: ["first", "second"],
            currentEntryID: "second"
        )

        #expect(position.canTransition(direction) == expected)
    }

    @Test
    func unknownCurrentEntryCannotTransition() {
        let position = PlaybackQueuePosition(
            entryIDs: ["first", "second"],
            currentEntryID: "missing"
        )

        #expect(!position.canTransition(.previous))
        #expect(!position.canTransition(.next))
    }
}
