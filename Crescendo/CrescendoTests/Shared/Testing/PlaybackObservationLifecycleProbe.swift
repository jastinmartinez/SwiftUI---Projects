import ComposableArchitecture

@testable import Crescendo

struct PlaybackObservationLifecycleProbe: Sendable {
    private let subscriptions: AsyncStream<Int>
    private let subscriptionsContinuation: AsyncStream<Int>.Continuation
    private let cancellations: AsyncStream<Int>
    private let cancellationsContinuation: AsyncStream<Int>.Continuation
    private let observationContinuations = LockIsolated<
        [AsyncStream<PlaybackObservation>.Continuation]
    >([])

    init() {
        (subscriptions, subscriptionsContinuation) = AsyncStream<Int>.makeStream()
        (cancellations, cancellationsContinuation) = AsyncStream<Int>.makeStream()
    }

    func observations() async -> AsyncStream<PlaybackObservation> {
        AsyncStream { continuation in
            let subscription = observationContinuations.withValue {
                $0.append(continuation)
                return $0.count
            }
            subscriptionsContinuation.yield(subscription)
            continuation.onTermination = { _ in
                cancellationsContinuation.yield(subscription)
            }
        }
    }

    func waitForSubscription(_ expectedSubscription: Int) async {
        var iterator = subscriptions.makeAsyncIterator()
        while let subscription = await iterator.next() {
            if subscription == expectedSubscription { return }
        }
    }

    func waitForCancellation(_ expectedSubscription: Int) async {
        var iterator = cancellations.makeAsyncIterator()
        while let subscription = await iterator.next() {
            if subscription == expectedSubscription { return }
        }
    }

    func yield(
        _ snapshot: PlaybackSnapshot,
        toSubscription subscription: Int
    ) {
        observationContinuations.value[subscription - 1].yield(.snapshot(snapshot))
    }

    func finish(subscription: Int) {
        observationContinuations.value[subscription - 1].finish()
    }
}
