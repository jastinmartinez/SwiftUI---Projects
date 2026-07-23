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
            navigate: { try await provider.navigate($0) },
            setRepeat: { await provider.setRepeat($0) },
            setShuffle: { await provider.setShuffle($0) }
        )
    }
}
