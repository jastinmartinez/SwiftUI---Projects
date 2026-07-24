extension PlaybackItemClient {
    static func live(
        preparer: AVPlayerItemPreparer,
        installer: AVPlayerItemInstaller
    ) -> Self {
        Self(
            load: { resource in
                let item = try await preparer.prepare(resource)
                try await installer.install(item, for: resource)
            }
        )
    }
}
