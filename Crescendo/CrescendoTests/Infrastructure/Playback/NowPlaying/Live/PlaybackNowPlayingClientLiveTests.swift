import ComposableArchitecture
import Foundation
import MediaPlayer
import Testing
import UIKit

@testable import Crescendo

@MainActor
@Suite(.serialized)
struct PlaybackNowPlayingClientLiveTests {
    @Test
    func textPublishesBeforeArtworkCompletes() async throws {
        let probe = SuspendedOperationProbe<Data>()
        let client = makeClient(
            image: NowPlayingImageClient(
                load: { _ in try await probe.run() }
            )
        )

        await client.publish(
            makeProjection(
                id: "immediate",
                title: "Immediate",
                artworkURL: try artworkURL("immediate")
            )
        )
        await probe.waitUntilStarted()

        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Immediate")
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil)

        await client.clear()
        await probe.waitUntilCancelled()
    }

    @Test
    func matchingArtworkAugmentsCurrentMetadata() async throws {
        let probe = SuspendedOperationProbe<Data>()
        let client = makeClient(
            image: NowPlayingImageClient(
                load: { _ in try await probe.run() }
            )
        )

        await client.publish(
            makeProjection(
                id: "matching",
                title: "Matching",
                artworkURL: try artworkURL("matching")
            )
        )
        await probe.waitUntilStarted()
        probe.succeed(with: artworkData())
        await waitUntil {
            infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork]
                is MPMediaItemArtwork
        }

        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Matching")

        await client.clear()
    }

    @Test
    func publishingAnotherTrackCancelsPendingArtwork() async throws {
        let probe = SuspendedOperationProbe<Data>()
        let client = makeClient(
            image: NowPlayingImageClient(
                load: { _ in try await probe.run() }
            )
        )

        await client.publish(
            makeProjection(
                id: "first",
                title: "First",
                artworkURL: try artworkURL("first")
            )
        )
        await probe.waitUntilStarted()
        await client.publish(
            makeProjection(
                id: "second",
                title: "Second",
                artworkURL: nil
            )
        )
        await probe.waitUntilCancelled()

        #expect(probe.hasObservedCancellation)
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Second")
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil)

        await client.clear()
    }

    @Test
    func cancellationIgnoringArtworkCannotOverwriteAnotherTrack() async throws {
        let probe = CancellationIgnoringArtworkProbe()
        let client = makeClient(
            image: NowPlayingImageClient(load: { _ in await probe.run() })
        )

        await client.publish(
            makeProjection(
                id: "stale",
                title: "Stale",
                artworkURL: try artworkURL("stale")
            )
        )
        await probe.waitUntilStarted()
        await client.publish(
            makeProjection(
                id: "current",
                title: "Current",
                artworkURL: nil
            )
        )
        probe.succeed(with: artworkData())
        await drainUnstructuredTasks()

        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Current")
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil)

        await client.clear()
    }

    @Test
    func clearInvalidatesCancellationIgnoringArtwork() async throws {
        let probe = CancellationIgnoringArtworkProbe()
        let client = makeClient(
            image: NowPlayingImageClient(load: { _ in await probe.run() })
        )

        await client.publish(
            makeProjection(
                id: "cleared",
                title: "Cleared",
                artworkURL: try artworkURL("cleared")
            )
        )
        await probe.waitUntilStarted()
        await client.clear()
        probe.succeed(with: artworkData())
        await drainUnstructuredTasks()

        #expect(infoCenter.nowPlayingInfo == nil)
    }

    @Test
    func missingArtworkURLDoesNotLoad() async throws {
        let loadCallCount = LockIsolated(0)
        let client = makeClient(
            image: NowPlayingImageClient(
                load: { _ in
                    loadCallCount.withValue { $0 += 1 }
                    return Data()
                }
            )
        )

        await client.publish(
            makeProjection(
                id: "text-only",
                title: "Text Only",
                artworkURL: nil
            )
        )

        #expect(loadCallCount.value == 0)
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Text Only")

        await client.clear()
    }

    @Test
    func artworkFailurePreservesCurrentMetadata() async throws {
        let probe = SuspendedOperationProbe<Data>()
        let client = makeClient(
            image: NowPlayingImageClient(
                load: { _ in try await probe.run() }
            )
        )

        await client.publish(
            makeProjection(
                id: "failure",
                title: "Still Visible",
                artworkURL: try artworkURL("failure")
            )
        )
        await probe.waitUntilStarted()
        probe.fail(with: ArtworkFailure.unavailable)
        await drainUnstructuredTasks()

        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Still Visible")
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil)

        await client.clear()
    }

    @Test
    func invalidArtworkDataPreservesCurrentMetadata() async throws {
        let client = makeClient(
            image: NowPlayingImageClient(
                load: { _ in Data("not an image".utf8) }
            )
        )

        await client.publish(
            makeProjection(
                id: "invalid-image",
                title: "Still Text",
                artworkURL: try artworkURL("invalid-image")
            )
        )
        await drainUnstructuredTasks()

        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Still Text")
        #expect(infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] == nil)

        await client.clear()
    }

    private var infoCenter: MPNowPlayingInfoCenter {
        MPNowPlayingInfoCenter.default()
    }

    private func makeClient(
        image: NowPlayingImageClient
    ) -> PlaybackNowPlayingClient {
        infoCenter.nowPlayingInfo = nil
        return PlaybackNowPlayingClient.live(
            infoCenter: infoCenter,
            image: image
        )
    }

    private func makeProjection(
        id: String,
        title: String,
        artworkURL: URL?
    ) -> PlaybackNowPlayingClient.Projection {
        PlaybackNowPlayingClient.Projection(
            item: .init(
                id: TrackID(providerID: .jamendo, nativeID: id),
                title: title,
                artistName: "The Tests",
                albumTitle: "Concurrency",
                artworkURL: artworkURL
            ),
            transport: .init(status: .playing),
            timeline: .init(position: 12, duration: 180),
            queue: .init(index: 0, count: 2)
        )
    }

    private func artworkURL(_ id: String) throws -> URL {
        try #require(URL(string: "https://example.com/\(id).png"))
    }

    private func artworkData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
            .pngData { context in
                UIColor.systemPurple.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while clock.now < deadline {
            if condition() { return }
            try? await clock.sleep(for: .milliseconds(10))
        }
        Issue.record("condition was not satisfied before the one-second deadline")
    }

    private func drainUnstructuredTasks() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }
}

private extension PlaybackNowPlayingClientLiveTests {
    enum ArtworkFailure: Error {
        case unavailable
    }

    final class CancellationIgnoringArtworkProbe: @unchecked Sendable {
        private let started: AsyncStream<Void>
        private let startedContinuation: AsyncStream<Void>.Continuation
        private let pendingContinuation =
            LockIsolated<CheckedContinuation<Data, Never>?>(nil)

        init() {
            (started, startedContinuation) = AsyncStream<Void>.makeStream()
        }

        func run() async -> Data {
            await withCheckedContinuation { continuation in
                pendingContinuation.withValue { $0 = continuation }
                startedContinuation.yield()
            }
        }

        func waitUntilStarted() async {
            var iterator = started.makeAsyncIterator()
            _ = await iterator.next()
            startedContinuation.finish()
        }

        func succeed(with data: Data) {
            pendingContinuation.withValue { continuation in
                continuation?.resume(returning: data)
                continuation = nil
            }
        }
    }
}
