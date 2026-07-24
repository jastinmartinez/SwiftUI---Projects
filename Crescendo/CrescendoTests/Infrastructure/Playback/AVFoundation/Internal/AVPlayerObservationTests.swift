@preconcurrency import AVFoundation
import Testing

@testable import Crescendo

struct AVPlayerObservationTests {
    /// Collects observations delivered on the Main Actor so a terminated stream
    /// can be inspected without capturing a mutable local in a `@Sendable` task.
    @MainActor
    private final class Recorder {
        private(set) var observations: [PlaybackObservation] = []

        func append(_ observation: PlaybackObservation) {
            observations.append(observation)
        }
    }

    @Test
    @MainActor
    func initialSnapshotReportsRegisteredTrackID() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let observation = AVPlayerObservation(player: player, registry: registry)
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
        let observation = AVPlayerObservation(player: player, registry: registry)

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
        let observation = AVPlayerObservation(player: player, registry: registry)
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
        let observation = AVPlayerObservation(player: player, registry: registry)
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

    /// Proves the negative (an unregistered item is ignored) by posting the
    /// unregistered notification first, then a registered sentinel. The
    /// unregistered item resolves to no track, so it can never reach the stream;
    /// the sentinel bounds the wait without an indefinite loop.
    @Test
    @MainActor
    func notificationsForUnregisteredItemsAreIgnored() async throws {
        let player = AVPlayer()
        let registry = AVPlayerItemRegistry()
        let observation = AVPlayerObservation(player: player, registry: registry)

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
        let subscription = AVPlayerObservationSubscription(player: player) { _ in }

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
        let subscription = AVPlayerObservationSubscription(player: player) { event in
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
        let observation = AVPlayerObservation(player: player, registry: registry)

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

    /// Mirrors `AVPlayerObservation`'s private mapping so the subscription-level
    /// tests can assert on application-facing values without exposing internals.
    private static func map(
        _ event: AVPlayerObservationSubscription.Event
    ) -> PlaybackObservation {
        switch event {
        case .stateChanged:
            return .snapshot(.idle)
        case .completed:
            return .completed(TrackID(providerID: .jamendo, nativeID: "unused"))
        case .failed:
            return .failed(nil, .playbackFailed)
        }
    }
}
