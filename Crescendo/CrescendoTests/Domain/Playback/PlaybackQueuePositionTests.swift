import Testing

@testable import Crescendo

struct PlaybackQueuePositionTests {
    @Test(arguments: [
        (PlaybackQueueNavigationDirection.previous, false),
        (.next, true),
    ])
    func firstEntryExposesOnlyTheNextTransition(
        direction: PlaybackQueueNavigationDirection,
        expected: Bool
    ) {
        let position = PlaybackQueuePosition(
            entryIDs: ["first", "second"],
            currentEntryID: "first"
        )

        #expect(position.canTransition(direction) == expected)
    }

    @Test(arguments: [
        (PlaybackQueueNavigationDirection.previous, true),
        (.next, false),
    ])
    func lastEntryExposesOnlyThePreviousTransition(
        direction: PlaybackQueueNavigationDirection,
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
