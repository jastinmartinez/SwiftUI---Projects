import ComposableArchitecture

extension PlaybackQueueClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension PlaybackQueueClient {
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            replace: {
                try await provider.replaceQueue(
                    itemIDs: $0,
                    startingItemID: $1
                )
            },
            previous: { try await provider.previous() },
            next: { try await provider.next() }
        )
    }
}
