@preconcurrency import AVFoundation
import Testing

@testable import Crescendo

struct AVPlayerObservationTests {
    @Test
    func idleSnapshotIsNotSeekable() {
        #expect(!PlaybackSnapshot.idle.isSeekable)
    }

    @Test
    @MainActor
    func initialSnapshotCarriesObservedSeekability() async {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let seekability = ItemSeekabilityObservationProbe(initialValue: true)
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live,
            itemSeekabilityObserver: seekability.observer
        )
        let item = AVPlayerItemFixture.make()
        let trackID = TrackID(providerID: .jamendo, nativeID: "seekable")
        registry.register(item, trackID: trackID)
        player.replaceCurrentItem(with: item)

        var iterator = observation.observations().makeAsyncIterator()
        let first = await iterator.next()

        guard case .snapshot(let snapshot) = first else {
            Issue.record(
                "expected an initial snapshot, got \(String(describing: first))"
            )
            return
        }
        #expect(snapshot.currentTrackID == trackID)
        #expect(snapshot.isSeekable)
    }

    @Test
    @MainActor
    func initialSnapshotReportsRegisteredTrackID() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live,
            itemSeekabilityObserver: .live
        )
        let item = AVPlayerItemFixture.make()
        let trackID = TrackID(providerID: .jamendo, nativeID: "initial")
        registry.register(item, trackID: trackID)
        player.replaceCurrentItem(with: item)

        var iterator = observation.observations().makeAsyncIterator()
        let first = await iterator.next()

        guard case .snapshot(let snapshot) = first else {
            Issue.record("expected an initial snapshot, got \(String(describing: first))")
            return
        }
        #expect(snapshot.currentTrackID == trackID)
        #expect(snapshot.status == .paused)
    }

    /// Approach (a) from the brief: identity resolution follows
    /// `player.currentItem` regardless of `timeControlStatus`, proven
    /// deterministically with two registered items. Forcing a live
    /// `.playing`/`.waiting` status requires real media playback and wall-clock
    /// waits, so this test isolates the identity mapping that the snapshot
    /// derives independently of transport status.
    @Test
    @MainActor
    func identityFollowsCurrentItemIndependentlyOfTransportStatus() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live,
            itemSeekabilityObserver: .live
        )

        let itemA = AVPlayerItemFixture.make()
        let trackA = TrackID(providerID: .jamendo, nativeID: "a")
        registry.register(itemA, trackID: trackA)
        let itemB = AVPlayerItemFixture.make()
        let trackB = TrackID(providerID: .localMusic, nativeID: "b")
        registry.register(itemB, trackID: trackB)

        player.replaceCurrentItem(with: itemA)
        var iterator = observation.observations().makeAsyncIterator()

        var resolvedA: TrackID?
        for _ in 0..<100 {
            guard case .snapshot(let snapshot) = await iterator.next() else { continue }
            if snapshot.currentTrackID == trackA {
                resolvedA = snapshot.currentTrackID
                break
            }
        }
        #expect(resolvedA == trackA)

        player.replaceCurrentItem(with: itemB)

        var resolvedB: TrackID?
        for _ in 0..<100 {
            guard case .snapshot(let snapshot) = await iterator.next() else { continue }
            if snapshot.currentTrackID == trackB {
                resolvedB = snapshot.currentTrackID
                break
            }
        }
        #expect(resolvedB == trackB)
    }

    @Test
    @MainActor
    func completionNotificationYieldsCompletedTrackID() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live,
            itemSeekabilityObserver: .live
        )
        let item = AVPlayerItemFixture.make()
        let trackID = TrackID(providerID: .jamendo, nativeID: "completed")
        registry.register(item, trackID: trackID)
        player.replaceCurrentItem(with: item)

        var iterator = observation.observations().makeAsyncIterator()
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )

        var completed: PlaybackObservation?
        for _ in 0..<100 {
            let next = await iterator.next()
            if case .completed = next {
                completed = next
                break
            }
        }
        #expect(completed == .completed(trackID))
    }

    @Test
    @MainActor
    func failureNotificationYieldsFailedTrackIDWithPlaybackFailed() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live,
            itemSeekabilityObserver: .live
        )
        let item = AVPlayerItemFixture.make()
        let trackID = TrackID(providerID: .jamendo, nativeID: "failed")
        registry.register(item, trackID: trackID)
        player.replaceCurrentItem(with: item)

        var iterator = observation.observations().makeAsyncIterator()
        NotificationCenter.default.post(
            name: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item
        )

        var failed: PlaybackObservation?
        for _ in 0..<100 {
            let next = await iterator.next()
            if case .failed = next {
                failed = next
                break
            }
        }
        #expect(failed == .failed(trackID, .playbackFailed))
    }

    @Test
    @MainActor
    func activeItemStatusFailureYieldsFailedTrackIDExactlyOnce() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let statusProbe = ItemStatusObservationProbe()
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: statusProbe.observer,
            itemSeekabilityObserver: .live
        )
        let item = AVPlayerItemFixture.make()
        let trackID = TrackID(providerID: .jamendo, nativeID: "status-failed")
        registry.register(item, trackID: trackID)
        player.replaceCurrentItem(with: item)

        var iterator = observation.observations().makeAsyncIterator()
        _ = await iterator.next()

        statusProbe.send(.failed, for: item)
        NotificationCenter.default.post(
            name: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item
        )
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )

        var failures: [PlaybackObservation] = []
        while let next = await iterator.next() {
            if case .failed = next {
                failures.append(next)
            }
            if case .completed = next {
                break
            }
        }

        #expect(failures == [.failed(trackID, .playbackFailed)])
    }

    @Test
    @MainActor
    func replacingCurrentItemInvalidatesOldStatusObservation() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let statusProbe = ItemStatusObservationProbe()
        let seekabilityProbe = ItemSeekabilityObservationProbe(
            initialValue: false
        )
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: statusProbe.observer,
            itemSeekabilityObserver: seekabilityProbe.observer
        )
        let oldItem = AVPlayerItemFixture.make()
        let oldTrackID = TrackID(providerID: .jamendo, nativeID: "old")
        registry.register(oldItem, trackID: oldTrackID)
        let currentItem = AVPlayerItemFixture.make()
        let currentTrackID = TrackID(providerID: .localMusic, nativeID: "current")
        registry.register(currentItem, trackID: currentTrackID)
        player.replaceCurrentItem(with: oldItem)

        var iterator = observation.observations().makeAsyncIterator()
        _ = await iterator.next()

        statusProbe.queue(.failed, for: oldItem)
        player.replaceCurrentItem(with: currentItem)
        var installedCurrentItem = false
        while let next = await iterator.next() {
            guard case .snapshot(let snapshot) = next else { continue }
            if snapshot.currentTrackID == currentTrackID {
                installedCurrentItem = true
                break
            }
        }
        #expect(installedCurrentItem)
        #expect(statusProbe.invalidationCount(for: oldItem) == 1)
        #expect(statusProbe.activeRegistrationCount(for: oldItem) == 0)
        #expect(statusProbe.activeRegistrationCount(for: currentItem) == 1)
        #expect(seekabilityProbe.invalidationCount == 1)

        statusProbe.send(.failed, for: oldItem)
        statusProbe.send(.failed, for: currentItem)
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: currentItem
        )

        var failures: [PlaybackObservation] = []
        while let next = await iterator.next() {
            if case .failed = next {
                failures.append(next)
            }
            if case .completed = next {
                break
            }
        }

        #expect(failures == [.failed(currentTrackID, .playbackFailed)])
    }

    @Test
    @MainActor
    func cancellingInvalidatesStatusObservationAndDropsQueuedCallback() async {
        let player = AVPlayer()
        let item = AVPlayerItemFixture.make()
        let statusProbe = ItemStatusObservationProbe()
        let seekabilityProbe = ItemSeekabilityObservationProbe(
            initialValue: false
        )
        player.replaceCurrentItem(with: item)

        let invalidatedRecorder = SubscriptionRecorder()
        let invalidatedSubscription = AVPlayerObservationSubscription(
            player: player,
            itemStatusObserver: statusProbe.observer,
            itemSeekabilityObserver: seekabilityProbe.observer,
            receive: invalidatedRecorder.receive
        )
        let queuedRecorder = SubscriptionRecorder()
        let queuedSubscription = AVPlayerObservationSubscription(
            player: player,
            itemStatusObserver: statusProbe.observer,
            itemSeekabilityObserver: seekabilityProbe.observer,
            receive: queuedRecorder.receive
        )
        let liveRecorder = SubscriptionRecorder()
        let liveSubscription = AVPlayerObservationSubscription(
            player: player,
            itemStatusObserver: statusProbe.observer,
            itemSeekabilityObserver: seekabilityProbe.observer,
            receive: liveRecorder.receive
        )
        await invalidatedRecorder.waitForStateChange()
        await queuedRecorder.waitForStateChange()
        await liveRecorder.waitForStateChange()

        invalidatedSubscription.cancel()
        #expect(statusProbe.invalidationCount == 1)
        #expect(statusProbe.activeRegistrationCount == 2)
        #expect(seekabilityProbe.invalidationCount == 1)

        statusProbe.queue(.failed, for: item)
        queuedSubscription.cancel()
        await Task.yield()
        await Task.yield()

        #expect(invalidatedRecorder.failedItems.isEmpty)
        #expect(queuedRecorder.failedItems.isEmpty)
        #expect(liveRecorder.failedItems.count == 1)
        #expect(statusProbe.invalidationCount == 2)
        #expect(statusProbe.activeRegistrationCount == 1)
        #expect(seekabilityProbe.invalidationCount == 2)

        liveSubscription.cancel()
        #expect(statusProbe.invalidationCount == 3)
        #expect(statusProbe.activeRegistrationCount == 0)
        #expect(seekabilityProbe.invalidationCount == 3)
    }

    @Test
    @MainActor
    func queuedCurrentItemChangeCannotRegisterStatusAfterCancellation() async {
        let player = AVPlayer()
        let initialItem = AVPlayerItemFixture.make()
        player.replaceCurrentItem(with: initialItem)
        let statusProbe = ItemStatusObservationProbe()
        let seekabilityProbe = ItemSeekabilityObservationProbe(
            initialValue: false
        )
        let subscription = AVPlayerObservationSubscription(
            player: player,
            itemStatusObserver: statusProbe.observer,
            itemSeekabilityObserver: seekabilityProbe.observer
        ) { _ in }
        let replacementItem = AVPlayerItemFixture.make()

        player.replaceCurrentItem(with: replacementItem)
        subscription.cancel()
        await Task.yield()
        await Task.yield()

        #expect(statusProbe.registrationCount == 1)
        #expect(statusProbe.invalidationCount == 1)
        #expect(statusProbe.activeRegistrationCount == 0)
        #expect(statusProbe.registrationCount(for: replacementItem) == 0)
        #expect(seekabilityProbe.invalidationCount == 1)
    }

    @Test
    @MainActor
    func replacedItemCannotEmitSeekabilityBeforeQueuedReplacementHandling() async {
        let player = AVPlayer()
        let itemA = AVPlayerItemFixture.make()
        player.replaceCurrentItem(with: itemA)
        let seekabilityProbe = ItemSeekabilityObservationProbe(
            initialValue: false
        )
        let recorder = SubscriptionRecorder()
        let subscription = AVPlayerObservationSubscription(
            player: player,
            itemStatusObserver: .live,
            itemSeekabilityObserver: seekabilityProbe.observer,
            receive: recorder.receive
        )
        await Task.yield()
        await Task.yield()
        recorder.resetStateChanges()

        let itemB = AVPlayerItemFixture.make()
        player.replaceCurrentItem(with: itemB)
        seekabilityProbe.send(true, for: itemA)

        #expect(recorder.seekabilityValues.isEmpty)
        subscription.cancel()
    }

    @Test
    @MainActor
    func rapidReplacementBackToSameItemStartsANewFailureLifecycle() async {
        let player = AVPlayer()
        let itemA = AVPlayerItemFixture.make()
        let itemB = AVPlayerItemFixture.make()
        player.replaceCurrentItem(with: itemA)
        let statusProbe = ItemStatusObservationProbe()
        let seekabilityProbe = ItemSeekabilityObservationProbe(
            initialValue: false
        )
        let recorder = SubscriptionRecorder()
        let subscription = AVPlayerObservationSubscription(
            player: player,
            itemStatusObserver: statusProbe.observer,
            itemSeekabilityObserver: seekabilityProbe.observer,
            receive: recorder.receive
        )

        statusProbe.send(.failed, for: itemA)
        #expect(recorder.failedItems.count == 1)

        player.replaceCurrentItem(with: itemB)
        player.replaceCurrentItem(with: itemA)
        await Task.yield()
        await Task.yield()

        #expect(statusProbe.registrationCount(for: itemA) == 2)
        #expect(statusProbe.invalidationCount(for: itemA) == 1)
        #expect(statusProbe.registrationCount(for: itemB) == 1)
        #expect(statusProbe.invalidationCount(for: itemB) == 1)
        #expect(statusProbe.activeRegistrationCount(for: itemA) == 1)
        #expect(statusProbe.activeRegistrationCount(for: itemB) == 0)
        #expect(seekabilityProbe.invalidationCount == 2)

        statusProbe.send(.failed, for: itemA)

        #expect(recorder.failedItems.count == 2)
        #expect(recorder.failedItems.allSatisfy { $0 === itemA })
        subscription.cancel()
    }

    @Test
    @MainActor
    func reinstallingItemStartsANewFailureLifecycle() async {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let statusProbe = ItemStatusObservationProbe()
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: statusProbe.observer,
            itemSeekabilityObserver: .live
        )
        let item = AVPlayerItemFixture.make()
        let trackID = TrackID(providerID: .jamendo, nativeID: "reinstalled")
        registry.register(item, trackID: trackID)
        let alternateItem = AVPlayerItemFixture.make()
        let alternateTrackID = TrackID(providerID: .localMusic, nativeID: "alternate")
        registry.register(alternateItem, trackID: alternateTrackID)
        player.replaceCurrentItem(with: item)

        var iterator = observation.observations().makeAsyncIterator()
        _ = await iterator.next()

        statusProbe.send(.failed, for: item)
        var firstFailure: PlaybackObservation?
        while let next = await iterator.next() {
            guard case .failed = next else { continue }
            firstFailure = next
            break
        }
        #expect(firstFailure == .failed(trackID, .playbackFailed))

        player.replaceCurrentItem(with: alternateItem)
        while let next = await iterator.next() {
            guard case .snapshot(let snapshot) = next else { continue }
            if snapshot.currentTrackID == alternateTrackID {
                break
            }
        }
        player.replaceCurrentItem(with: item)
        while let next = await iterator.next() {
            guard case .snapshot(let snapshot) = next else { continue }
            if snapshot.currentTrackID == trackID {
                break
            }
        }

        statusProbe.send(.failed, for: item)
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: item
        )
        var failures: [PlaybackObservation] = []
        while let next = await iterator.next() {
            if case .failed = next {
                failures.append(next)
            }
            if case .completed = next {
                break
            }
        }

        #expect(failures == [.failed(trackID, .playbackFailed)])
    }

    /// Proves the negative (an unregistered item is ignored) by posting the
    /// unregistered notification first, then a registered sentinel. The
    /// unregistered item resolves to no track, so it can never reach the stream;
    /// the sentinel bounds the wait without an indefinite loop.
    @Test
    @MainActor
    func notificationsForUnregisteredItemsAreIgnored() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live,
            itemSeekabilityObserver: .live
        )

        let registeredItem = AVPlayerItemFixture.make()
        let registeredTrackID = TrackID(providerID: .jamendo, nativeID: "sentinel")
        registry.register(registeredItem, trackID: registeredTrackID)
        player.replaceCurrentItem(with: registeredItem)

        let unregisteredItem = AVPlayerItemFixture.make()

        var iterator = observation.observations().makeAsyncIterator()
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: unregisteredItem
        )
        NotificationCenter.default.post(
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: registeredItem
        )

        var completed: PlaybackObservation?
        for _ in 0..<100 {
            let next = await iterator.next()
            if case .completed = next {
                completed = next
                break
            }
        }
        // The only completion that can reach the stream is the registered
        // sentinel; the unregistered item resolves to no track and is dropped.
        #expect(completed == .completed(registeredTrackID))
    }

    @Test
    @MainActor
    func cancellingTwiceRemainsSafe() async throws {
        let player = AVPlayer()
        let seekabilityProbe = ItemSeekabilityObservationProbe(
            initialValue: false
        )
        let subscription = AVPlayerObservationSubscription(
            player: player,
            itemStatusObserver: .live,
            itemSeekabilityObserver: seekabilityProbe.observer
        ) { _ in }

        subscription.cancel()
        subscription.cancel()
    }

    /// After cancellation the subscription must deliver no further events even
    /// when a KVO-triggering mutation occurs. `Task.yield()` drains the
    /// cooperative queue without any wall-clock wait.
    @Test
    @MainActor
    func cancellingRemovesObserversAndPeriodicObservation() async throws {
        let player = AVPlayer()
        let recorder = Recorder()
        let seekabilityProbe = ItemSeekabilityObservationProbe(
            initialValue: false
        )
        let subscription = AVPlayerObservationSubscription(
            player: player,
            itemStatusObserver: .live,
            itemSeekabilityObserver: seekabilityProbe.observer
        ) { event in
            recorder.append(Self.map(event))
        }

        subscription.cancel()

        player.replaceCurrentItem(with: AVPlayerItemFixture.make())
        await Task.yield()
        await Task.yield()

        #expect(recorder.observations.isEmpty)
    }

    /// Terminating the stream (by breaking out of iteration) drops the async
    /// iterator, which fires `onTermination` and cancels the subscription. A
    /// subsequent KVO-triggering mutation must not produce any further stream
    /// element.
    @Test
    @MainActor
    func noQueuedCallbackEmitsAfterCancellation() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let observation = AVPlayerObservation(
            player: player,
            registry: registry,
            itemStatusObserver: .live,
            itemSeekabilityObserver: .live
        )

        let itemA = AVPlayerItemFixture.make()
        registry.register(itemA, trackID: TrackID(providerID: .jamendo, nativeID: "a"))
        let itemB = AVPlayerItemFixture.make()
        registry.register(itemB, trackID: TrackID(providerID: .localMusic, nativeID: "b"))
        player.replaceCurrentItem(with: itemA)

        let recorder = Recorder()
        let task = Task { @MainActor in
            var count = 0
            for await observed in observation.observations() {
                recorder.append(observed)
                count += 1
                if count >= 1 { break }
            }
        }
        await task.value

        // Let onTermination's cancellation task run before mutating again.
        await Task.yield()
        await Task.yield()

        player.replaceCurrentItem(with: itemB)
        await Task.yield()
        await Task.yield()

        #expect(recorder.observations.count == 1)
    }

    // MARK: - Helpers

    /// Collects observations delivered on the Main Actor so a terminated stream
    /// can be inspected without capturing a mutable local in a `@Sendable` task.
    @MainActor
    private final class Recorder {
        private(set) var observations: [PlaybackObservation] = []

        func append(_ observation: PlaybackObservation) {
            observations.append(observation)
        }
    }

    /// Records raw subscription events and allows tests to wait until initializer
    /// registration has delivered its initial player-state callback.
    @MainActor
    private final class SubscriptionRecorder {
        private(set) var failedItems: [AVPlayerItem] = []
        private(set) var seekabilityValues: [Bool] = []
        private var receivedStateChange = false
        private var stateChangeWaiters: [CheckedContinuation<Void, Never>] = []

        func receive(_ event: AVPlayerObservationSubscription.Event) {
            switch event {
            case .stateChanged(let isSeekable):
                seekabilityValues.append(isSeekable)
                receivedStateChange = true
                for waiter in stateChangeWaiters {
                    waiter.resume()
                }
                stateChangeWaiters.removeAll()

            case .completed:
                break

            case .failed(let item):
                failedItems.append(item)
            }
        }

        func waitForStateChange() async {
            guard !receivedStateChange else { return }
            await withCheckedContinuation { continuation in
                stateChangeWaiters.append(continuation)
            }
        }

        func resetStateChanges() {
            seekabilityValues.removeAll()
            receivedStateChange = false
        }
    }

    /// Provides deterministic status callbacks and lifecycle-shaped tokens while
    /// tests retain real in-memory AVPlayerItem instances.
    @MainActor
    private final class ItemStatusObservationProbe {
        private final class Registration {
            let item: AVPlayerItem
            let receive: @MainActor (AVPlayerItem.Status) -> Void
            var isInvalidated = false

            init(
                item: AVPlayerItem,
                receive: @escaping @MainActor (AVPlayerItem.Status) -> Void
            ) {
                self.item = item
                self.receive = receive
            }
        }

        private var registrations: [Registration] = []

        var registrationCount: Int {
            registrations.count
        }

        var invalidationCount: Int {
            registrations.count(where: \.isInvalidated)
        }

        var activeRegistrationCount: Int {
            registrations.count { !$0.isInvalidated }
        }

        var observer: AVPlayerItemStatusObserver {
            AVPlayerItemStatusObserver { [weak self] item, receive in
                guard let self else {
                    return AVPlayerItemStatusObserver.Token(invalidate: {})
                }
                let registration = Registration(
                    item: item,
                    receive: receive
                )
                registrations.append(registration)
                return AVPlayerItemStatusObserver.Token {
                    registration.isInvalidated = true
                }
            }
        }

        func registrationCount(for item: AVPlayerItem) -> Int {
            registrations.count { $0.item === item }
        }

        func invalidationCount(for item: AVPlayerItem) -> Int {
            registrations.count {
                $0.item === item && $0.isInvalidated
            }
        }

        func activeRegistrationCount(for item: AVPlayerItem) -> Int {
            registrations.count {
                $0.item === item && !$0.isInvalidated
            }
        }

        func send(
            _ status: AVPlayerItem.Status,
            for item: AVPlayerItem
        ) {
            let receives =
                registrations
                .filter { !$0.isInvalidated && $0.item === item }
                .map(\.receive)
            for receive in receives {
                receive(status)
            }
        }

        func queue(
            _ status: AVPlayerItem.Status,
            for item: AVPlayerItem
        ) {
            let receives =
                registrations
                .filter { !$0.isInvalidated && $0.item === item }
                .map(\.receive)
            Task { @MainActor in
                for receive in receives {
                    receive(status)
                }
            }
        }
    }

    @MainActor
    private final class ItemSeekabilityObservationProbe {
        private final class Registration {
            let item: AVPlayerItem
            let receive: @MainActor (Bool) -> Void
            var isInvalidated = false

            init(
                item: AVPlayerItem,
                receive: @escaping @MainActor (Bool) -> Void
            ) {
                self.item = item
                self.receive = receive
            }
        }

        private let initialValue: Bool
        private var registrations: [Registration] = []

        var invalidationCount: Int {
            registrations.count(where: \.isInvalidated)
        }

        init(initialValue: Bool) {
            self.initialValue = initialValue
        }

        var observer: AVPlayerItemSeekabilityObserver {
            AVPlayerItemSeekabilityObserver { [weak self] item, receive in
                guard let self else {
                    return AVPlayerItemSeekabilityObserver.Token(invalidate: {})
                }
                let registration = Registration(
                    item: item,
                    receive: receive
                )
                registrations.append(registration)
                receive(initialValue)
                return AVPlayerItemSeekabilityObserver.Token {
                    registration.isInvalidated = true
                }
            }
        }

        func send(
            _ isSeekable: Bool,
            for item: AVPlayerItem
        ) {
            let receives =
                registrations
                .filter { !$0.isInvalidated && $0.item === item }
                .map(\.receive)
            for receive in receives {
                receive(isSeekable)
            }
        }
    }

    /// Mirrors `AVPlayerObservation`'s private mapping so the subscription-level
    /// tests can assert on application-facing values without exposing internals.
    private static func map(
        _ event: AVPlayerObservationSubscription.Event
    ) -> PlaybackObservation {
        switch event {
        case .stateChanged(_):
            return .snapshot(.idle)
        case .completed:
            return .completed(TrackID(providerID: .jamendo, nativeID: "unused"))
        case .failed:
            return .failed(nil, .playbackFailed)
        }
    }
}
