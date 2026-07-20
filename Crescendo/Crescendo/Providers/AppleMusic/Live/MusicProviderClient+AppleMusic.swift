import ComposableArchitecture

extension MusicProviderClient: DependencyKey {
    static let liveValue = MusicProviderClient.appleMusic
}

extension MusicProviderClient {
    /// Connects provider-neutral operations to one session-scoped Apple Music provider.
    static let appleMusic: MusicProviderClient = {
        let appleMusicProvider = AppleMusicProvider()

        return MusicProviderClient(
            currentAccess: {
                await appleMusicProvider.currentAccess()
            },
            requestAccess: {
                await appleMusicProvider.requestAccess()
            },
            search: { query, limit in
                try await appleMusicProvider.search(query, limit: limit)
            },
            play: { itemID in
                try await appleMusicProvider.play(itemID)
            },
            resume: {
                try await appleMusicProvider.resume()
            },
            pause: {
                await appleMusicProvider.pause()
            },
            stop: {
                await appleMusicProvider.stop()
            },
            seek: { time in
                await appleMusicProvider.seek(to: time)
            },
            playbackSnapshots: {
                await appleMusicProvider.playbackSnapshots()
            }
        )
    }()
}
