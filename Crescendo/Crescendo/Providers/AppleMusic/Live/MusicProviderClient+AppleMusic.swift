import ComposableArchitecture

extension MusicProviderClient: DependencyKey {
    static let liveValue = Self.appleMusic(AppleMusicProvider())
}

extension MusicProviderClient {
    /// Connects provider-neutral operations to one session-scoped Apple Music provider.
    static func appleMusic(_ provider: AppleMusicProvider) -> Self {
        Self(
            currentAccess: {
                await provider.currentAccess()
            },
            requestAccess: {
                await provider.requestAccess()
            },
            search: { query, limit in
                try await provider.search(query, limit: limit)
            },
            play: { itemID in
                try await provider.play(itemID)
            },
            resume: {
                try await provider.resume()
            },
            pause: {
                await provider.pause()
            },
            stop: {
                await provider.stop()
            },
            seek: { time in
                await provider.seek(to: time)
            },
            playbackSnapshots: {
                await provider.playbackSnapshots()
            }
        )
    }
}
